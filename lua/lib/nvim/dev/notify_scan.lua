---@module 'lib.nvim.dev.notify_scan'
--- Where do sibling plugin repos emit user-facing messages? Finds every
--- `vim.notify`, `nvim_echo`, `nvim_err_write(ln)`, `:echoerr`/`:echomsg` and
--- `print(` call, plus load-time bindings of `vim.notify` and calls through
--- `lib.nvim.notify`, so a repo can be moved onto `lib.nvim.notify.popup`
--- (toast + history instead of a `:messages` more-prompt).
---@description
--- A line scanner, not a parser: it reads each `lua/` and `plugin/` file of
--- every immediate subdirectory of `root` and matches call sites by pattern.
--- Good enough to build a migration worklist; it can miss a message built in a
--- way no pattern anticipates, and it reports a call inside a string as a call.
---
--- Per finding it records the kind, the log level when it is spelled out on
--- the call line or the next few lines, and the head of the first string
--- literal. Two derived flags matter for a migration:
---
---   * `dynamic` -- the first argument is not a string literal, i.e. the call
---     is (or sits inside) a wrapper: converting that one function converts
---     every caller. These are the central conversion points.
---   * `bound` -- `local notify = vim.notify` at module load. Such a binding
---     bypasses any hook installed later, so it must be resolved at call time.
---
--- Not scanned: `TESTS/`, `tests/`, `.deps/`, `.git/`, `node_modules/`,
--- `lib.nvim`, `ui.nvim` and anything listed in `opts.exclude`.

local M = {}

---@class Lib.Dev.NotifyScan.Finding
---@field repo string
---@field file string Path relative to the repo
---@field line integer
---@field kind string "notify"|"bound"|"echo"|"err_write"|"echo_cmd"|"print"|"lib_notify"
---@field level string|nil "ERROR"|"WARN"|"INFO"|"DEBUG"|"TRACE" or nil when not spelled out
---@field text string Head of the first string literal on the call ("" when dynamic)
---@field dynamic boolean First argument is not a string literal
---@field multiline boolean The literal contains "\n" or the call builds text with table.concat

---@class Lib.Dev.NotifyScan.Opts
---@field exclude? string[] Extra repo directory names to skip

local ALWAYS_EXCLUDED = { ["lib.nvim"] = true, ["ui.nvim"] = true }
local SKIP_DIRS =
  { TESTS = true, tests = true, [".deps"] = true, [".git"] = true, node_modules = true }

-- kind, Lua pattern (matched against the line with comments stripped).
local CALLS = {
  { "bound", "=%s*vim%.notify%s*$" },
  { "bound", "=%s*vim%.notify%s*[,%)]" },
  { "notify", "vim%.notify%s*%(" },
  { "notify", "vim%.notify_once%s*%(" },
  { "echo", "nvim_echo%s*%(" },
  { "err_write", "nvim_err_writeln%s*%(" },
  { "err_write", "nvim_err_write%s*%(" },
  { "echo_cmd", "[\"']%s*echoerr%s" },
  { "echo_cmd", "[\"']%s*echomsg%s" },
  { "echo_cmd", "vim%.cmd%.echoerr" },
  { "lib_notify", "lib%.nvim%.notify" },
  { "lib_notify", "notify%.create%s*%(" },
  { "lib_notify", "create_safe%s*%(" },
  { "print", "%f[%w_]print%s*%(" },
}

---@param path string
---@return string[]
local function read_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and lines or {}
end

---Removes a trailing `-- comment` when it is not inside a string. Cheap and
---approximate: a `--` after an odd number of quotes is kept.
---@param line string
---@return string
local function strip_comment(line)
  local pos = line:find("%-%-")
  while pos do
    local before = line:sub(1, pos - 1)
    local _, dq = before:gsub('"', "")
    local _, sq = before:gsub("'", "")
    if dq % 2 == 0 and sq % 2 == 0 then
      return before
    end
    pos = line:find("%-%-", pos + 2)
  end
  return line
end

---@param window string Call line plus the next few lines
---@return string|nil
local function find_level(window)
  local named = window:match("vim%.log%.levels%.(%u+)")
  if named then
    return named
  end
  local numbered = window:match(",%s*([0-5])%s*[,%)]")
  local by_number =
    { ["0"] = "TRACE", ["1"] = "DEBUG", ["2"] = "INFO", ["3"] = "WARN", ["4"] = "ERROR" }
  return numbered and by_number[numbered] or nil
end

---@param window string
---@param after integer Byte index just past the opening "(" of the call
---@return string text, boolean dynamic, boolean multiline
local function analyse_argument(window, after)
  local rest = window:sub(after):gsub("^%s+", "")
  local literal = rest:match('^"([^"]*)') or rest:match("^'([^']*)")
  if literal then
    local multi = literal:find("\\n", 1, true) ~= nil
    return literal:sub(1, 70), false, multi
  end
  -- A `{ { "text", ... } }` chunk list (nvim_echo) starts with two braces.
  local chunk = rest:match('^{%s*{%s*"([^"]*)')
  if chunk then
    return chunk:sub(1, 70), false, chunk:find("\\n", 1, true) ~= nil
  end
  local multi = window:find("table%.concat") ~= nil
  return "", true, multi
end

---@param repo_dir string
---@param repo string
---@return Lib.Dev.NotifyScan.Finding[]
local function scan_repo(repo_dir, repo)
  local out = {}
  local files = {}
  for _, sub in ipairs({ "lua", "plugin" }) do
    local base = repo_dir .. "/" .. sub
    if vim.fn.isdirectory(base) == 1 then
      for name, kind in
        vim.fs.dir(base, {
          depth = 20,
          skip = function(dir)
            return not SKIP_DIRS[dir]
          end,
        })
      do
        if kind == "file" and name:sub(-4) == ".lua" then
          files[#files + 1] = sub .. "/" .. name
        end
      end
    end
  end
  table.sort(files)

  for _, rel in ipairs(files) do
    local lines = read_lines(repo_dir .. "/" .. rel)
    for i, raw in ipairs(lines) do
      if not raw:match("^%s*%-%-") then
        local line = strip_comment(raw)
        for _, def in ipairs(CALLS) do
          local from, to = line:find(def[2])
          -- Only the log-level helper is imported from lib.nvim.notify here.
          if from and def[1] == "lib_notify" and line:find("resolve_log_level", 1, true) then
            from = nil
          end
          if from then
            local window = table.concat(vim.list_slice(lines, i, math.min(#lines, i + 4)), "\n")
            local text, dynamic, multiline = "", false, false
            if def[1] ~= "bound" and def[1] ~= "lib_notify" and def[1] ~= "print" then
              text, dynamic, multiline = analyse_argument(window, to + 1)
            elseif def[1] == "print" then
              text, dynamic, multiline = analyse_argument(window, to + 1)
            end
            out[#out + 1] = {
              repo = repo,
              file = rel,
              line = i,
              kind = def[1],
              level = def[1] == "print" and nil or find_level(window),
              text = text,
              dynamic = dynamic,
              multiline = multiline,
            }
            break -- one finding per line
          end
        end
      end
    end
  end
  return out
end

---Scans every sibling repo under `root`.
---@param root? string Directory holding the repos (default: cwd)
---@param opts? Lib.Dev.NotifyScan.Opts
---@return Lib.Dev.NotifyScan.Finding[]
function M.scan(root, opts)
  root = root or vim.fn.getcwd()
  local skip = vim.tbl_extend("force", {}, ALWAYS_EXCLUDED)
  for _, name in ipairs(opts and opts.exclude or {}) do
    skip[name] = true
  end

  local all = {}
  for _, name in ipairs(vim.fn.readdir(root) or {}) do
    local dir = root .. "/" .. name
    if not skip[name] and vim.fn.isdirectory(dir .. "/lua") == 1 then
      vim.list_extend(all, scan_repo(dir, name))
    end
  end
  return all
end

---Per-repo totals, most findings first.
---@param findings Lib.Dev.NotifyScan.Finding[]
---@return { repo: string, total: integer, by_kind: table<string, integer>, dynamic: integer, bound: integer, multiline: integer, errors: integer }[]
function M.summarize(findings)
  local by_repo = {}
  for _, f in ipairs(findings) do
    local r = by_repo[f.repo]
      or {
        repo = f.repo,
        total = 0,
        by_kind = {},
        dynamic = 0,
        bound = 0,
        multiline = 0,
        errors = 0,
      }
    by_repo[f.repo] = r
    r.total = r.total + 1
    r.by_kind[f.kind] = (r.by_kind[f.kind] or 0) + 1
    if f.dynamic and f.kind ~= "print" and f.kind ~= "bound" and f.kind ~= "lib_notify" then
      r.dynamic = r.dynamic + 1
    end
    if f.kind == "bound" then
      r.bound = r.bound + 1
    end
    if f.multiline then
      r.multiline = r.multiline + 1
    end
    if f.level == "ERROR" or f.level == "WARN" then
      r.errors = r.errors + 1
    end
  end
  local list = vim.tbl_values(by_repo)
  table.sort(list, function(a, b)
    return a.total > b.total
  end)
  return list
end

---Markdown report: a summary table, then the findings per repo.
---@param root? string
---@param opts? Lib.Dev.NotifyScan.Opts
---@return string[]
function M.lines(root, opts)
  local findings = M.scan(root, opts)
  local lines = {
    "| Repo | Findings | Wrapper-like | Load-time bound | Multiline | WARN/ERROR | Kinds |",
    "|---|---|---|---|---|---|---|",
  }
  for _, r in ipairs(M.summarize(findings)) do
    local kinds = {}
    for kind, n in pairs(r.by_kind) do
      kinds[#kinds + 1] = kind .. "=" .. n
    end
    table.sort(kinds)
    lines[#lines + 1] = ("| %s | %d | %d | %d | %d | %d | %s |"):format(
      r.repo,
      r.total,
      r.dynamic,
      r.bound,
      r.multiline,
      r.errors,
      table.concat(kinds, " ")
    )
  end

  local current
  for _, f in ipairs(findings) do
    if f.repo ~= current then
      current = f.repo
      lines[#lines + 1] = ""
      lines[#lines + 1] = "### " .. f.repo
      lines[#lines + 1] = ""
    end
    lines[#lines + 1] = ("- `%s:%d` %s%s%s%s %s"):format(
      f.file,
      f.line,
      f.kind,
      f.level and (" " .. f.level) or "",
      f.dynamic and f.kind ~= "bound" and f.kind ~= "lib_notify" and " (dynamic)" or "",
      f.multiline and " (multiline)" or "",
      f.text ~= "" and ("`" .. f.text .. "`") or ""
    )
  end
  return lines
end

---Expose `:<name> [path]` for the calling config. Put this call in **your own
---config**, not in a library, like every other `create_usercmd` in lib.nvim.
---@param name? string Default `LibNotifyScan`
---@return nil
function M.create_usercmd(name)
  local base = name or "LibNotifyScan"
  require("lib.nvim.bindings.usercmd").create(base, function(cmd_opts)
    local root = cmd_opts.args ~= "" and vim.fn.fnamemodify(cmd_opts.args, ":p"):gsub("[/\\]$", "")
      or nil
    local lines = M.lines(root)
    local ok, kit = pcall(require, "lib.nvim.ui.kit")
    if ok then
      kit.viewer({
        lines = lines,
        title = " " .. base .. " ",
        width = math.min(140, vim.o.columns - 8),
      })
    else
      print(table.concat(lines, "\n"))
    end
  end, {
    nargs = "?",
    complete = "dir",
    desc = "Where sibling repos emit user messages (vim.notify / nvim_echo / print) -- popup migration worklist",
  })
end

return M
