---@module 'lib.nvim.cross.platform.is_windows'
--- Single-purpose module that exports exactly one function to detect
--- whether Neovim is running on native Windows (not WSL).
--- The module returns the function itself (not a table).

-- Cache across calls, declared outside the returned function so it is a
-- shared upvalue (not reset to nil on every invocation — a `local cached`
-- declared *inside* the function body would never actually persist).
---@type boolean|nil
local cached

---@return boolean
--- Returns true when the current runtime is native Windows.
return function()
  if cached ~= nil then
    return cached
  end

  -- Prefer `vim.uv` (Neovim ≥ 0.10); fall back to `vim.loop` for older versions.
  local uv = (vim and (vim.uv or vim.loop)) or nil

  local is = false

  -- uname-based detection (sysname == "Windows_NT" on Windows)
  if uv and uv.os_uname then
    local ok, u = pcall(uv.os_uname)
    if ok and type(u) == "table" and type(u.sysname) == "string" then
      if u.sysname == "Windows_NT" then
        is = true
      end
    end
  end

  -- Environment variable fallback (present on Windows, absent on Linux/macOS)
  if not is and vim and vim.env then
    if type(vim.env.OS) == "string" and vim.env.OS:lower():find("windows", 1, true) then
      is = true
    end
  end

  cached = is
  return is
end

