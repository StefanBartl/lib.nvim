---@module 'lib.nvim.fs.path'

---@diagnostic disable-next-line: deprecated
local unpack = table.unpack or unpack

local M = {}

--- True if `path` is already absolute (Windows drive, UNC, or POSIX root).
---@param path string
---@return boolean
local function is_absolute(path)
  return path:match("^%a:[\\/]") ~= nil -- C:\ or C:/
    or path:match("^[\\/][\\/]") ~= nil -- \\share or //share
    or path:match("^/") ~= nil -- /posix
end

--- Resolve a repository-root-relative path to an absolute one.
---
--- Tools like LazyGit hand back paths relative to the repository root
--- (forward slashes), which the caller (e.g. a Neovim instance driven via
--- `nvr`) must resolve itself. `raw` that is already absolute is returned
--- normalized as-is; otherwise the first readable candidate wins, trying
--- the Git root of the current working directory, then the cwd itself.
---@param raw string repo-root-relative (or absolute) path
---@return string absolute path with OS-native separators
function M.from_repo_relative(raw)
  if is_absolute(raw) then
    return vim.fn.fnamemodify(raw, ":p")
  end

  local candidates = {} ---@type string[]

  local repo_root = require("lib.nvim.git").repo_root()
  if repo_root and repo_root ~= "" then
    candidates[#candidates + 1] = repo_root .. "/" .. raw
  end

  candidates[#candidates + 1] = vim.fn.fnamemodify(raw, ":p")

  for _, cand in ipairs(candidates) do
    if vim.fn.filereadable(cand) == 1 then
      return cand
    end
  end

  return candidates[#candidates]
end

---@param parts string[]
---@return string
function M.joinpath(parts)
  if vim.fs and vim.fs.joinpath then
    return vim.fs.joinpath(unpack(parts))
  end

  -- Fallback: use platform separator
  local sep = package.config:sub(1, 1)
  return table.concat(parts, sep)
end

-- Utility: ensure directory for a given path exists; returns true on success.
-- Uses vim.fn.mkdir with "p" flag to create parents; returns boolean.
---@param path string
---@return boolean, string?
function M.ensure_dir(path)
  if not path or path == "" then
    return false, "empty path"
  end
  local dir = vim.fn.fnamemodify(path, ":h")
  if dir == "" or dir == "." then
    -- current directory; nothing to do
    return true
  end
  -- If dir already exists, done.
  if vim.loop.fs_stat(dir) then
    return true
  end
  local ok, err = pcall(vim.fn.mkdir, dir, "p")
  if ok then
    -- mkdir returns 1 on success; verify dir exists now
    if vim.loop.fs_stat(dir) then
      return true
    else
      return false, "mkdir did not create directory"
    end
  else
    return false, tostring(err)
  end
end

return M
