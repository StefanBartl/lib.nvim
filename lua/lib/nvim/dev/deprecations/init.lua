---@module 'lib.nvim.dev.deprecations'
--- Deprecation watcher: finds deprecated Neovim calls (`vim.loop`,
--- `nvim_buf_set_option`, `vim.highlight`, `vim.lsp.get_active_clients`, ...)
--- that are still in your Lua code, and says so on save or in `:checkhealth`.
---@description
--- Lives in lib.nvim rather than in migrate.nvim, which deliberately has no
--- watcher: the detection is a small, dependency-free line scanner, the save
--- hook and the health section are a few lines each, and every plugin and
--- config already has lib.nvim on the runtime path. A standalone mini plugin
--- would add an install step for the same code.
---
--- A line scanner, not a parser. Before the rule patterns run, each line has
--- its comments and string contents blanked out (columns preserved), with the
--- state of an open long string or block comment (`[[ ]]`, `--[==[ ]==]`)
--- carried from line to line -- a deprecated name inside a string literal or
--- a comment is not a call. What it cannot see: a call built at runtime
--- (`vim[name]`), an alias bound elsewhere (`local api = vim.api` is fine, the
--- pattern matches the function name; `local loop = vim.loop` is reported at
--- the binding, not at each use). A `---@diagnostic disable-next-line:
--- deprecated` on the line above, or `disable-line: deprecated` on the line
--- itself, silences that line -- the same marker LuaLS honours, so a gated
--- fallback for older Neovim is waived once for both.
---
--- Nothing here runs at startup: `watch()` registers one `BufWritePost`
--- autocmd, the rule table is loaded on the first scan.

local M = {}

---@class Lib.Dev.Deprecations.Rule
---@field id string Name of the deprecated call, also the finding's id
---@field key? string Plain text every matching line contains, checked before the pattern;
---  default: the id's last segment (`loop` of `vim.loop`) when the pattern spells it out
---@field pattern string Lua pattern matched against the line with comments/strings blanked
---@field replacement string What to use instead (human-readable)
---@field since string Neovim version that deprecated it ("0.10"); the rule is skipped on older Neovim
---@field unless? string Lua pattern: a line matching it (on the blanked line) is not reported

---@class Lib.Dev.Deprecations.Finding
---@field lnum integer 1-based line
---@field col integer 1-based byte column of the match
---@field id string Rule id
---@field replacement string
---@field since string
---@field file? string Set by `scan_roots` / `scan_file`

---@class Lib.Dev.Deprecations.Opts
---@field rules? Lib.Dev.Deprecations.Rule[] Replaces the default rule table
---@field extra_rules? Lib.Dev.Deprecations.Rule[] Appended to the (default or given) rules
---@field max_lines? integer A buffer/file longer than this is not scanned (default 20000)
---@field max_files? integer `scan_roots` stops after this many files (default 2000)

local DEFAULT_MAX_LINES = 20000
local DEFAULT_MAX_FILES = 2000
---Not descended into by `scan_roots`: dot-directories (`.git`, `.deps`, a
---`.claude/worktrees` full of checkout copies) and `node_modules`.
---@param dir string
---@return boolean
local function skip_dir(dir)
  local base = vim.fs.basename(dir)
  return base:sub(1, 1) == "." or base == "node_modules"
end

local SUPPRESS_NEXT = "@diagnostic%s+disable%-next%-line:[^\n]*deprecated"
local SUPPRESS_LINE = "@diagnostic%s+disable%-line:[^\n]*deprecated"

---The rules active on the running Neovim: default (or `opts.rules`) plus
---`opts.extra_rules`, minus every rule whose `since` is newer than this Neovim.
---@param opts? Lib.Dev.Deprecations.Opts
---@return Lib.Dev.Deprecations.Rule[]
function M.active_rules(opts)
  local base = opts and opts.rules or require("lib.nvim.dev.deprecations.rules")
  local extra = opts and opts.extra_rules or {}
  local out = {}
  for _, list in ipairs({ base, extra }) do
    for _, rule in ipairs(list) do
      if vim.fn.has("nvim-" .. rule.since) == 1 then
        out[#out + 1] = rule
      end
    end
  end
  return out
end

---Blank out comments and string contents of one line, keeping its length, so
---that byte columns of what remains are the columns of the original line.
---`close` is the delimiter of a long string / block comment still open from an
---earlier line (`"]]"`, `"]==]"`) or nil; the second return is the same for the
---next line.
---@param line string
---@param close string|nil
---@return string masked, string|nil close
function M.mask(line, close)
  local n = #line
  local out = {}
  local i = 1
  if close then
    local _, e = line:find(close, 1, true)
    if not e then
      return (" "):rep(n), close
    end
    out[1] = (" "):rep(e)
    i = e + 1
  end
  local seg = i -- start of the pending code segment
  while true do
    local p = line:find("[%-%[\"']", i)
    if not p then
      break
    end
    local c = line:sub(p, p)
    local blank_from, blank_to, open -- range to blank; `open` = unclosed long delimiter
    if c == "-" then
      if line:sub(p + 1, p + 1) == "-" then
        local eq = line:match("^%[(=*)%[", p + 2)
        if eq then
          local delim = "]" .. eq .. "]"
          local _, e = line:find(delim, p + 4 + #eq, true)
          blank_from, blank_to = p, e or n
          open = not e and delim or nil
        else
          blank_from, blank_to = p, n
        end
      end
    elseif c == "[" then
      local eq = line:match("^%[(=*)%[", p)
      if eq then
        local delim = "]" .. eq .. "]"
        local _, e = line:find(delim, p + 2 + #eq, true)
        blank_from, blank_to = p, e or n
        open = not e and delim or nil
      end
    else -- a quote: runs to the matching unescaped quote, or to the line end
      local j = p + 1
      while j <= n do
        local d = line:sub(j, j)
        if d == "\\" then
          j = j + 2
        elseif d == c then
          break
        else
          j = j + 1
        end
      end
      blank_from, blank_to = p, math.min(j, n)
    end
    if blank_from then
      out[#out + 1] = line:sub(seg, blank_from - 1)
      out[#out + 1] = (" "):rep(blank_to - blank_from + 1)
      if open then
        return table.concat(out), open
      end
      i = blank_to + 1
      seg = i
    else
      i = p + 1
    end
  end
  out[#out + 1] = line:sub(seg)
  return table.concat(out), nil
end

---@param lines string[]
---@param rules Lib.Dev.Deprecations.Rule[]
---@return Lib.Dev.Deprecations.Finding[]
local function scan_with(lines, rules)
  local out = {}
  local close = nil
  -- A plain-text key per rule ("loop", "nvim_buf_set_option") is far cheaper
  -- to look for than the pattern, and a line without it cannot match. Derived
  -- from the id only when the pattern itself spells it out, so a custom rule
  -- whose id is just a label still runs its pattern on every line.
  local keys = {}
  for r = 1, #rules do
    local rule = rules[r]
    local key = rule.key
    if key == nil then
      local last = rule.id:match("[%w_]+$")
      local literal = rule.pattern:gsub("%%(.)", "%1")
      key = last and literal:find(last, 1, true) and last or ""
    end
    keys[r] = key
  end
  for lnum = 1, #lines do
    local raw = lines[lnum]
    local masked
    if close and not raw:find(close, 1, true) then
      masked = nil -- the whole line is inside a long string / block comment
    else
      -- Prefilter: only lines that could hold a hit, or that can change the
      -- long-bracket state, pay for the masking.
      local candidate = false
      for r = 1, #rules do
        if raw:find(keys[r], 1, true) and raw:find(rules[r].pattern) then -- "" always found
          candidate = true
          break
        end
      end
      if candidate or close or raw:find("[", 1, true) then
        masked, close = M.mask(raw, close)
      end
      if not candidate then
        masked = nil
      end
    end

    if
      masked
      and not raw:find(SUPPRESS_LINE)
      and not (lnum > 1 and lines[lnum - 1]:find(SUPPRESS_NEXT))
    then
      for r = 1, #rules do
        local rule = rules[r]
        if not (rule.unless and masked:find(rule.unless)) then
          local from, to = masked:find(rule.pattern)
          while from do
            out[#out + 1] = {
              lnum = lnum,
              col = from,
              id = rule.id,
              replacement = rule.replacement,
              since = rule.since,
            }
            from, to = masked:find(rule.pattern, math.max(to, from) + 1)
          end
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.lnum ~= b.lnum then
      return a.lnum < b.lnum
    end
    return a.col < b.col
  end)
  return out
end

---Scan Lua source lines.
---@param lines string[]
---@param opts? Lib.Dev.Deprecations.Opts
---@return Lib.Dev.Deprecations.Finding[]
function M.scan_lines(lines, opts)
  if #lines > ((opts and opts.max_lines) or DEFAULT_MAX_LINES) then
    return {}
  end
  return scan_with(lines, M.active_rules(opts))
end

---Scan a loaded buffer (default: current).
---@param buf? integer
---@param opts? Lib.Dev.Deprecations.Opts
---@return Lib.Dev.Deprecations.Finding[]
function M.scan_buffer(buf, opts)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if not vim.api.nvim_buf_is_valid(buf) then
    return {}
  end
  if vim.api.nvim_buf_line_count(buf) > ((opts and opts.max_lines) or DEFAULT_MAX_LINES) then
    return {}
  end
  return scan_with(vim.api.nvim_buf_get_lines(buf, 0, -1, false), M.active_rules(opts))
end

---@param path string
---@param rules Lib.Dev.Deprecations.Rule[]
---@param max_lines integer
---@return Lib.Dev.Deprecations.Finding[]
local function scan_path(path, rules, max_lines)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or #lines > max_lines then
    return {}
  end
  -- A `---@meta` file is LuaLS annotations, not code that runs: its
  -- `vim.loop = uv` declares the alias, it does not use it.
  if lines[1] and lines[1]:find("^%-%-%-@meta") then
    return {}
  end
  local found = scan_with(lines, rules)
  for _, f in ipairs(found) do
    f.file = path
  end
  return found
end

---Scan one file from disk.
---@param path string
---@param opts? Lib.Dev.Deprecations.Opts
---@return Lib.Dev.Deprecations.Finding[]
function M.scan_file(path, opts)
  return scan_path(path, M.active_rules(opts), (opts and opts.max_lines) or DEFAULT_MAX_LINES)
end

---Scan every `*.lua` file under each root (a root may also be a single file).
---Skips dot-directories and `node_modules/`, never follows a symlink, and
---leaves out `---@meta` annotation files.
---@param roots string[]
---@param opts? Lib.Dev.Deprecations.Opts
---@return Lib.Dev.Deprecations.Finding[] findings, boolean truncated
function M.scan_roots(roots, opts)
  local rules = M.active_rules(opts)
  local max_lines = (opts and opts.max_lines) or DEFAULT_MAX_LINES
  local max_files = (opts and opts.max_files) or DEFAULT_MAX_FILES
  local files = {}
  local truncated = false
  for _, root in ipairs(roots) do
    root = vim.fs.normalize(root)
    if vim.fn.isdirectory(root) == 1 then
      for name, kind in
        vim.fs.dir(root, {
          depth = 20,
          skip = function(dir)
            return not skip_dir(dir)
          end,
        })
      do
        if kind == "file" and name:sub(-4) == ".lua" then
          if #files >= max_files then
            truncated = true
            break
          end
          files[#files + 1] = root .. "/" .. name
        end
      end
    elseif vim.fn.filereadable(root) == 1 then
      files[#files + 1] = root
    end
  end
  table.sort(files)
  local all = {}
  for _, path in ipairs(files) do
    vim.list_extend(all, scan_path(path, rules, max_lines))
  end
  return all, truncated
end

---One finding as `12:5 vim.loop -> vim.uv (deprecated since 0.10)`.
---@param f Lib.Dev.Deprecations.Finding
---@return string
function M.format(f)
  return ("%d:%d %s -> %s (deprecated since %s)"):format(
    f.lnum,
    f.col,
    f.id,
    f.replacement,
    f.since
  )
end

---Report deprecated calls under `roots` through `vim.health` -- for
---`:checkhealth lib` (which passes `stdpath("config")`) and for a plugin's own
---`health.lua` (pass the plugin's root).
---@param roots? string[] Default `{ stdpath("config") }`
---@param opts? Lib.Dev.Deprecations.Opts|{ title?: string, max_listed?: integer }
---@return integer count Number of findings
function M.health(roots, opts)
  roots = roots or { vim.fn.stdpath("config") }
  local h = vim.health
  h.start((opts and opts.title) or "lib.nvim: deprecated API calls")
  local findings, truncated = M.scan_roots(roots, opts)
  if truncated then
    h.info(("stopped after %d files"):format((opts and opts.max_files) or DEFAULT_MAX_FILES))
  end
  if #findings == 0 then
    h.ok("no deprecated calls in " .. table.concat(roots, ", "))
    return 0
  end
  local max_listed = (opts and opts.max_listed) or 50
  for i, f in ipairs(findings) do
    if i > max_listed then
      h.info(("... and %d more"):format(#findings - max_listed))
      break
    end
    h.warn(("%s:%s"):format(vim.fn.fnamemodify(f.file, ":~"), M.format(f)), {
      "Use " .. f.replacement,
      "Silence a deliberate fallback with ---@diagnostic disable-next-line: deprecated",
    })
  end
  return #findings
end

local GROUP = "lib_nvim_dev_deprecations"

---@class Lib.Dev.Deprecations.WatchOpts: Lib.Dev.Deprecations.Opts
---@field pattern? string|string[] Autocmd pattern (default "*.lua")
---@field max_listed? integer Findings listed in the warning (default 5)
---@field on_findings? fun(findings: Lib.Dev.Deprecations.Finding[], buf: integer) Replaces the warning

---Warn after each save of a Lua buffer that still has deprecated calls. Put
---this one line in **your own config**; calling it again replaces the earlier
---watcher. A save without findings is silent.
---@param opts? Lib.Dev.Deprecations.WatchOpts
---@return integer autocmd_id
function M.watch(opts)
  opts = opts or {}
  local autocmd = require("lib.nvim.bindings.autocmd")
  return autocmd.create("BufWritePost", function(args)
    local findings = M.scan_buffer(args.buf, opts)
    if #findings == 0 then
      return
    end
    if opts.on_findings then
      opts.on_findings(findings, args.buf)
      return
    end
    local max_listed = opts.max_listed or 5
    local lines = {
      ("%s: %d deprecated call(s)"):format(
        vim.fn.fnamemodify(vim.api.nvim_buf_get_name(args.buf), ":t"),
        #findings
      ),
    }
    for i = 1, math.min(#findings, max_listed) do
      lines[#lines + 1] = "  " .. M.format(findings[i])
    end
    if #findings > max_listed then
      lines[#lines + 1] = ("  ... and %d more"):format(#findings - max_listed)
    end
    require("lib.nvim.notify").create("[deprecations]").warn(table.concat(lines, "\n"))
  end, {
    group = autocmd.group(GROUP, true),
    pattern = opts.pattern or "*.lua",
    desc = "lib.nvim.dev.deprecations: warn about deprecated calls after saving",
  })
end

---Remove the watcher installed by `watch()`.
---@return nil
function M.unwatch()
  require("lib.nvim.bindings.autocmd").group(GROUP, true)
end

return M
