---@module 'lib.nvim.fs.is_readable_file'

-- Ensure the path is valid
---@param filepath string
---@return boolean
return function(filepath)
if vim.fn.filereadable(filepath) ~= 1 and vim.fn.isdirectory(filepath) ~= 1 then
  return false
end
  return true
end
