---@meta
---@module 'lib.@types.misc'

---@class OsShell
---@field prog string        -- executable to spawn (e.g. "sh" or "powershell")
---@field args string[]      -- arguments vector (no command yet)
---@field is_powershell boolean

---@class OsRunResult
---@field code integer
---@field signal integer
---@field stdout string
---@field stderr string

---@alias Lib.Cross.Platform.PlatformName
---| '"windows"'
---| '"wsl"'
---| '"macos"'
---| '"linux"'

return {}
