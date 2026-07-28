---@module 'lib.nvim.fs.is_dir'
--- True when `p` exists and is a directory.

---@param p string
---@return boolean
return function(p)
  local st = vim.uv.fs_stat(p)
  return (st and st.type == "directory") or false
end
