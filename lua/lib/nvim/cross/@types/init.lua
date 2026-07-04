---@meta
---@module 'lib.nvim.cross.@types'

---@class Lib.Cross
---@field platform Lib.Cross.Platform
---@field run Lib.Cross.Run
---@field clipboard Lib.Cross.Clipboard
---@field fs Lib.Cross.Fs
---@field separators Lib.Cross.Separators

---@class Lib.Cross.ALL
---@field is_windows fun(): boolean
---@field is_wsl fun(): boolean
---@field is_macos fun(): boolean
---@field is_linux fun(): boolean
---@field is fun(platform?: Lib.Cross.Platform.PlatformName): boolean|Lib.Cross.Platform.PlatformName
---@field shell fun(): OsShell
---@field run fun(cmd: string, cb: fun(ok:boolean, res:OsRunResult)): nil
---@field run_blocking fun(cmd: string): OsRunResult
---@field copy_to_clipboard fun(text: string): boolean
---@field run_blocking fun(cmd: string[], input?: string): boolean, string|nil # Low-level argv-based process runner with stdin support.

return {}
