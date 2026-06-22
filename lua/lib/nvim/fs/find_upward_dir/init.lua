---@module 'lib.nvim.fs.find_upward_dir'

---@param names string[]
---@param from string
---@return string|nil
return function(names, from)
  local found = vim.fs.find(names, { path = from, upward = true })
  if found and found[1] then
    return vim.fs.dirname(found[1])
  end
  return nil
end
