---@module 'lib.nvim.cross.platform.is_macos'
--- Single-purpose module that exports exactly one function to detect
--- whether Neovim is running on macOS (Darwin).
--- The module returns the function itself (not a table).

-- Cache across calls, declared outside the returned function so it is a
-- shared upvalue (not reset to nil on every invocation).
---@type boolean|nil
local cached

---@return boolean
--- Returns true when the current runtime is macOS.
return function()
  if cached ~= nil then
    return cached
  end

  local uv = (vim and (vim.uv or vim.loop)) or nil

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

