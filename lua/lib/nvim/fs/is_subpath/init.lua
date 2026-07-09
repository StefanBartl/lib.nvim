---@module 'lib.nvim.fs.is_subpath'

-- `vim.fs.normalize` always returns forward-slash paths (on every OS, including
-- Windows) — so the separator used below must be "/" too. An earlier version used
-- `package.config:sub(1,1)` (the native separator, "\" on Windows) to append the
-- trailing separator, which meant the appended "\" never matched the
-- forward-slash-normalized path prefix: `is_subpath` returned false for every
-- genuine subpath on Windows.
local norm = vim.fs.normalize

---@param path string
---@param base string
---@return boolean
return function(path, base)
  path, base = norm(path), norm(base)
  if path == base then
    return true
  end
  if #path <= #base then
    return false
  end
  if base:sub(-1) ~= "/" then
    base = base .. "/"
  end
  return path:sub(1, #base) == base
end
