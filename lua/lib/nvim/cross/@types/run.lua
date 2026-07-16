---@meta
---@module 'lib.nvim.cross.@types.run'

---@class Lib.Cross.Run
---@field shell fun(): OsShell
---@field run fun(cmd: string, cb: fun(ok:boolean, res:OsRunResult)): nil
---@field run_blocking fun(cmd: string): OsRunResult
---@field run_detached fun(argv: string[]): boolean, string|nil # Launch argv detached (fire-and-forget); routes through jobstart on Windows/WSL since vim.system detach is unreliable there for GUI processes.
---@field run_argv { run_blocking: fun(cmd: string[], input?: string): boolean, string|nil }

return {}
