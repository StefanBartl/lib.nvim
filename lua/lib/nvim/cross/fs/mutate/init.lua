---@module 'lib.nvim.cross.fs.mutate'
--- Injection-safe file mutation primitives, built directly on libuv (no shell
--- involved) — safe to use with untrusted/user-controlled paths.

local M = {}

local function uv()
  return vim.uv or vim.loop
end

---@param path string
---@return boolean ok
---@return string|nil err
function M.delete_file(path)
  local ok, err = uv().fs_unlink(path)
  if not ok then
    return false, err
  end
  return true, nil
end

---@param src string
---@param dst string
---@return boolean ok
---@return string|nil err
function M.copy_file(src, dst)
  local ok, err = uv().fs_copyfile(src, dst)
  if not ok then
    return false, err
  end
  return true, nil
end

---@param src string
---@param dst string
---@return boolean ok
---@return string|nil err
function M.rename_file(src, dst)
  local ok, err = uv().fs_rename(src, dst)
  if not ok then
    return false, err
  end
  return true, nil
end

---Create `path` and all missing parent directories (`mkdir -p` semantics),
---without invoking a shell.
---@param path string
---@return boolean ok
---@return string|nil err
function M.mkdir_p(path)
  local ok, err = pcall(vim.fn.mkdir, path, "p")
  if not ok then
    return false, tostring(err)
  end
  return true, nil
end

return M
