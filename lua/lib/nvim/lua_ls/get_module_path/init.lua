---@module 'lib.nvim.lua_ls.get_module_path'

---Convert file path to Lua module path
---@param filepath string Absolute path to file
---@return string|nil module_path
return function (filepath)
  local normalized = filepath:gsub("\\", "/")
  local lua_idx = normalized:find("/lua/")
  if not lua_idx then
    return nil
  end

  local after_lua = normalized:sub(lua_idx + 5)
  local without_ext = after_lua:gsub("%.lua$", "")
  without_ext = without_ext:gsub("/init$", "")
  local module_path = without_ext:gsub("/", ".")

  return module_path
end
