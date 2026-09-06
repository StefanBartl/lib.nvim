---@module 'lib.nvim.dev.duplicates'
--- Identical function bodies across sibling repos — candidates for
--- extraction into lib.nvim itself, not a general clone-detector.
---@description
--- Promoted from a throwaway `python docs/ROADMAP/tools/duplicate_functions.py`
--- in nvim-config, which walked a hardcoded `E:/repos`. This does the same
--- detection — normalize each top-level function body (strip blank/comment
--- lines and leading indent), group by the normalized text, keep only groups
--- that span two or more different repos — parameterized by a root directory
--- instead.
---
--- **Scope: `root`'s immediate subdirectories, not `root` itself.** A hit
--- only means something when the *same* body shows up in *two different
--- repos*, so the unit being compared is "a subdirectory of `root` that
--- looks like a plugin" (has a `lua/` folder), not `root` as one repo. Point
--- it at a directory that holds several sibling checkouts — `E:\repos`, or
--- any parent of two or more plugin repos — cwd by default. Pointing it at
--- a single plugin's own root (no sibling checkouts underneath) finds
--- nothing, correctly: there is no second repo to duplicate against.
---
--- lib.nvim itself is always excluded from the repo set — the question this
--- answers is "what should move INTO lib.nvim", so lib.nvim's own code is
--- never itself a duplication candidate.

local M = {}

--- A two-line wrapper is not worth extracting.
local MIN_LINES = 4

---@class Lib.Dev.Duplicates.Hit
---@field repo string        # subdirectory name under `root`
---@field rel string         # path relative to that repo, forward-slashed
---@field name string        # function name as written (may be dotted/colon-qualified)
---@field n_lines integer

---@class Lib.Dev.Duplicates.Group
---@field n_lines integer
---@field repos string[]                     # every distinct repo involved, sorted
---@field hits Lib.Dev.Duplicates.Hit[]

---@internal
--- Immediate subdirectories of `root` that look like a plugin (have a
--- `lua/` folder), excluding `lib.nvim` itself.
---@param root string
---@return string[]
local function candidate_repos(root)
  local out = {}
  for _, name in ipairs(vim.fn.readdir(root) or {}) do
    if name ~= "lib.nvim" and vim.fn.isdirectory(root .. "/" .. name .. "/lua") == 1 then
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end

---@internal
--- Every top-level `(local )function NAME(...) ... end` in `text`, `end`
--- matched at column 0 — the same simplification the original regex made
--- (`^end$`, greedy-least): a nested function whose own inner block ends
--- with a column-0 `end` would close early. Rare in this codebase's own
--- style (nested blocks are indented), and a false split only ever shortens
--- a body, never merges two unrelated ones, so it can undercount matches but
--- cannot manufacture one.
---@param text string
---@return { name: string, lines: string[] }[]
local function functions_in(text)
  local out = {}
  local lines = vim.split(text, "\n", { plain = true })
  local i = 1
  while i <= #lines do
    local name = lines[i]:match("^local function%s+([%w_.:]+)%s*%(")
      or lines[i]:match("^function%s+([%w_.:]+)%s*%(")
    if name then
      local body = {}
      local j = i + 1
      while j <= #lines and lines[j] ~= "end" do
        body[#body + 1] = lines[j]
        j = j + 1
      end
      if j <= #lines then -- found a matching column-0 `end`, not EOF
        out[#out + 1] = { name = name, lines = body }
      end
      i = j + 1
    else
      i = i + 1
    end
  end
  return out
end

---@internal
--- Body lines, normalized for comparison: trimmed, blank and comment-only
--- lines dropped, joined with `\n`. Two functions differing only in
--- whitespace or a comment compare equal; two differing in one real line do
--- not.
---@param lines string[]
---@return { text: string, n_lines: integer }|nil  nil if fewer than MIN_LINES real lines remain
local function normalize(lines)
  local kept = {}
  for _, ln in ipairs(lines) do
    local t = vim.trim(ln)
    if t ~= "" and not t:match("^%-%-") then
      kept[#kept + 1] = t
    end
  end
  if #kept < MIN_LINES then
    return nil
  end
  return { text = table.concat(kept, "\n"), n_lines = #kept }
end

---Scan every plugin repo under `root` for function bodies shared by two or
---more of them.
---@param root string|nil  directory holding sibling repos; default cwd
---@return Lib.Dev.Duplicates.Group[]  sorted by how many repos share a hit, most first
function M.scan(root)
  root = (root or vim.fn.getcwd()):gsub("\\", "/"):gsub("/+$", "")

  ---@type table<string, Lib.Dev.Duplicates.Hit[]>
  local bodies = {}

  for _, repo in ipairs(candidate_repos(root)) do
    local base = root .. "/" .. repo .. "/lua"
    local files = vim.fs.find(function(name)
      return name:match("%.lua$") ~= nil
    end, { path = base, type = "file", limit = math.huge })
    for _, path in ipairs(files) do
      local fd = io.open(path, "r")
      if fd then
        local text = fd:read("*a")
        fd:close()
        for _, fn in ipairs(functions_in(text)) do
          local norm = normalize(fn.lines)
          if norm then
            local rel = path:sub(#base + 2)
            bodies[norm.text] = bodies[norm.text] or {}
            local list = bodies[norm.text]
            list[#list + 1] = { repo = repo, rel = rel, name = fn.name, n_lines = norm.n_lines }
          end
        end
      end
    end
  end

  ---@type Lib.Dev.Duplicates.Group[]
  local groups = {}
  for _, hits in pairs(bodies) do
    local repos = {}
    local seen = {}
    for _, h in ipairs(hits) do
      if not seen[h.repo] then
        seen[h.repo] = true
        repos[#repos + 1] = h.repo
      end
    end
    if #repos >= 2 then
      table.sort(repos)
      groups[#groups + 1] = { n_lines = hits[1].n_lines, repos = repos, hits = hits }
    end
  end

  table.sort(groups, function(a, b)
    if #a.repos ~= #b.repos then
      return #a.repos > #b.repos
    end
    return a.n_lines > b.n_lines
  end)
  return groups
end

--- CDX: rendered output uses German labels ("Zeilen", "Plugins", "identische
--- Funktionskoerper...") while every other lib.nvim user-facing string is
--- English; a leftover from the nvim-config Python-tool origin mentioned in
--- the module header.
---`scan()`, rendered as printable lines.
---@param root string|nil
---@return string[]
function M.lines(root)
  local groups = M.scan(root)
  local out = {}
  for _, g in ipairs(groups) do
    out[#out + 1] = ("## %d Zeilen, %d Plugins: %s"):format(
      g.n_lines,
      #g.repos,
      table.concat(g.repos, ", ")
    )
    for _, h in ipairs(g.hits) do
      out[#out + 1] = ("   %-22s %-46s %s"):format(h.repo, h.rel, h.name)
    end
    out[#out + 1] = ""
  end
  out[#out + 1] = ("identische Funktionskoerper in mehr als einem Plugin: %d"):format(#groups)
  return out
end

---Expose `:<name> [path]` for the calling config. Put this call in **your
---own config**, not in a library — same reasoning every other
---`create_usercmd` in lib.nvim gives.
---@param name string|nil  # Default `LibDuplicateScan`.
---@return nil
function M.create_usercmd(name)
  local base = name or "LibDuplicateScan"
  local usercmd = require("lib.nvim.bindings.usercmd")

  usercmd.create(base, function(opts)
    local root = opts.args ~= "" and vim.fn.fnamemodify(opts.args, ":p"):gsub("/$", "") or nil
    local lines = M.lines(root)
    local ok, kit = pcall(require, "lib.nvim.ui.kit")
    if ok then
      kit.viewer({
        lines = lines,
        title = " " .. base .. " ",
        width = math.min(120, vim.o.columns - 8),
      })
    else
      print(table.concat(lines, "\n"))
    end
  end, {
    nargs = "?",
    complete = "dir",
    desc = "Function bodies duplicated across sibling repos under a root (default cwd) -- lib.nvim extraction candidates",
  })
end

return M
