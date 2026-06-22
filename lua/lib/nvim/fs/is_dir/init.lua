---@module 'lib.nvim.fs.is_dir'

---@param p string
---@return boolean
return function(p)
  local st = vim.uv.fs_stat(p)
  return (st and st.type == "directory") or false
end
