---@module 'lib.nvim.cross.platform.is_linux'
--- Single-purpose module that exports exactly one function to detect
--- whether Neovim is running on Linux (excluding WSL).
--- The module returns the function itself (not a table).

-- Cache across calls, declared outside the returned function so it is a
-- shared upvalue (not reset to nil on every invocation).
---@type boolean|nil
local cached

---@return boolean
--- Returns true when the current runtime is Linux but not WSL.
return function()
  if cached ~= nil then
    return cached
  end

  local uv = (vim and (vim.uv or vim.loop)) or nil

  local is = false

  if uv and uv.os_uname then
    local ok, u = pcall(uv.os_uname)
    if ok and type(u) == "table" and u.sysname == "Linux" then
      -- Exclude WSL explicitly
      local rel = type(u.release) == "string" and u.release:lower() or ""
      if not rel:find("microsoft", 1, true) and not rel:find("wsl", 1, true) then
        is = true
      end
    end
  end

  cached = is
  return is
end

