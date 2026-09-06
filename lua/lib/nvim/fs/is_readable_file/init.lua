---@module 'lib.nvim.fs.is_readable_file'
--- True when `filepath` is a readable file **or** an existing directory
--- (despite the name).

---@param filepath string
---@return boolean
return function(filepath)
  if vim.fn.filereadable(filepath) ~= 1 and vim.fn.isdirectory(filepath) ~= 1 then
    return false
  end
  return true
end
