---@module 'lib.nvim.cross.platform.is_macos'
--- Single-purpose module that exports exactly one function to detect
--- whether Neovim is running on macOS (Darwin).
--- The module returns the function itself (not a table).

---@return boolean
--- Returns true when the current runtime is macOS.
return function()
  local uv = (vim and (vim.uv or vim.loop)) or nil

  ---@type boolean|nil
  local cached

  if cached ~= nil then
    return cached
  end

  local is = false

  if uv and uv.os_uname then
    local ok, u = pcall(uv.os_uname)
    if ok and type(u) == "table" and u.sysname == "Darwin" then
      is = true
    end
  end

  cached = is
  return is
end

