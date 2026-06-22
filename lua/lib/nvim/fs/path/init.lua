---@module 'lib.nvim.fs.path'

---@diagnostic disable-next-line: deprecated
local unpack = table.unpack or unpack

local M = {}

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
