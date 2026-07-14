---@module 'lib.nvim.fs.project_key'
--- Stable per-project cache key: prefers the Git root of `path` (default
--- cwd), falls back to `path`/cwd itself, and runs the result through
--- `lib.nvim.fs.normkey` so it's always absolute and canonical.
---
--- Uses the cached, marker-based `lib.nvim.fs.find_root` (marker ".git")
--- rather than shelling out to `git rev-parse` on every call.

local find_root = require("lib.nvim.fs.find_root")
local normkey = require("lib.nvim.fs.normkey")

local finder = find_root({ markers = { ".git" } })

---@param path? string Defaults to the current working directory
---@return string
return function(path)
  local from = path or (vim.uv or vim.loop).cwd() or vim.fn.getcwd()
  local root = finder.find(from)
  return normkey(root or from)
end
