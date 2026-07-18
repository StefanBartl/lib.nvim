---@meta
---@module 'lib.nvim.cross.@types'

---@class Lib.Cross
---@field platform Lib.Cross.Platform
---@field run Lib.Cross.Run
---@field clipboard Lib.Cross.Clipboard
---@field fs Lib.Cross.Fs
---@field separators Lib.Cross.Separators
---@field uv Lib.Cross.Uv

---Libuv-backed process helpers.
---@class Lib.Cross.Uv
---@field spawn_command fun(argv: string[], opts?: table): any # Fire-and-forget spawn with inherited stdio.
---@field spawn_shell_command fun(cmd: string, opts?: table): any # Same, but through the platform shell.
---@field spawn_capture Lib.Cross.Uv.SpawnCapture # Async argv spawn, output buffered, one callback at exit.
---@field spawn_stream Lib.Cross.Uv.SpawnStream # Async argv spawn, output streamed line by line.
---@field wait_until fun(predicate: fun(): boolean, opts?: table): any

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
