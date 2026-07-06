---@module 'lib.nvim.fs.ignore.list'

--- Canonical filesystem ignore definitions for developer tooling.
---
--- This module centralizes filesystem ignore rules shared across multiple
--- developer-facing tools (LSP, file pickers, file trees, search).
---
--- The data is intentionally heuristic and conservative.
--- It is NOT a replacement for .gitignore and performs no filesystem IO.

local M = {}

--- Exact directory or file basenames to ignore.
--- These are compared literally (no patterns).
--- @type string[]
M.basenames = {
  ".git",
  ".github",
  ".hg",
  ".svn",
  ".svc",
  ".stfolder",
  ".stversions",

  ".agents",
  ".claude",

  "node_modules",
  ".pnpm-store",
  ".yarn",

  ".venv",
  ".direnv",

  "__pycache__",
  ".mypy_cache",
  ".pytest_cache",

  ".cache",
  ".sass-cache",

  "build",
  "dist",
  "out",
  "target",
  "bin",
  "obj",

  "zig-cache",
  "zig-out",

  ".DS_Store",
  "thumbs.db",

  ".vscode",
  ".idea",
}

--- Lua-style patterns (used by Telescope / grep-like tools).
--- @type string[]
M.patterns = {
  "package%.lock.json",
  "pnpm%-lock.yaml",
  "yarn.lock",

  "%.class",
  "%.pyc",
  "%.log",
  "%.tmp",
  "%.cache",
}

--- Normalize a path or basename for platform-agnostic comparisons.
--- @param s string
--- @return string
function M.normalize(s)
  if type(s) ~= "string" then
    return s
  end

  s = s:gsub("[/\\]+$", "")

  if package.config:sub(1, 1) == "\\" then
    s = s:lower()
  end

  return s
end

--- Return basenames as a set for fast membership checks.
--- @return table<string, boolean>
function M.as_set()
  local set = {}
  for _, name in ipairs(M.basenames) do
    set[M.normalize(name)] = true
  end
  return set
end

--- Convert basenames to LuaLS workspace.ignoreDir glob patterns.
--- @return string[]
function M.as_luals_patterns()
  local out = {}
  for _, name in ipairs(M.basenames) do
    local n = M.normalize(name)
    out[#out + 1] = n
    out[#out + 1] = "**/" .. n
  end
  return out
end

--- Combine basenames and patterns for Telescope file_ignore_patterns.
--- @return string[]
function M.as_telescope_patterns()
  local out = {}

  for _, name in ipairs(M.basenames) do
    out[#out + 1] = name
  end

  for _, pat in ipairs(M.patterns) do
    out[#out + 1] = pat
  end

  return out
end

--- Basenames only for Neo-tree hide_by_name.
--- @return string[]
function M.as_neotree_names()
  local out = {}
  for i = 1, #M.basenames do
    out[i] = M.basenames[i]
  end
  return out
end

return M
