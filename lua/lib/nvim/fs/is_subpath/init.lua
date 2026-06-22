---@module 'lib.nvim.fs.is_subpath'

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
  local sep = package.config:sub(1, 1) or "/"
  if base:sub(-1) ~= sep then
    base = base .. sep
  end
  return path:sub(1, #base) == base
end
