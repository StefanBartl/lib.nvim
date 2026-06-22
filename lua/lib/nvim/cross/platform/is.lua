---@module 'lib.nvim.cross.platform.is'
--- Central platform-dispatch helper.
--- This module returns a single function with dual behavior:
---   1) When called without arguments, it returns the current platform as a string.
---   2) When called with a platform name, it returns whether the current platform matches it.

---@param platform? Lib.Cross.Platform.PlatformName
---@return boolean|string
--- If `platform` is provided, returns true if it matches the current platform.
--- If `platform` is nil, returns the detected platform string.
return function(platform)
  -- Import detectors (single-function modules)
  local is_windows = require("lib.nvim.cross.platform.is_windows")
  local is_wsl = require("lib.nvim.cross.platform.is_wsl")
  local is_macos = require("lib.nvim.cross.platform.is_macos")
  local is_linux = require("lib.nvim.cross.platform.is_linux")

  ---@type Lib.Cross.Platform.PlatformName
  local current

  -- Detection order matters:
  -- WSL must be detected before native Windows and Linux.
  if is_wsl() then
    current = "wsl"
  elseif is_windows() then
    current = "windows"
  elseif is_macos() then
    current = "macos"
  elseif is_linux() then
    current = "linux"
  else
    -- Fallback: unknown but treated as linux-like
    current = "linux"
  end

  if platform == nil then
    return current
  end

  return platform == current
end

