---@meta
---@module 'lib.nvim.cross.@types.run'

---@class Lib.Cross.Run
---@field shell fun(): OsShell
---@field run fun(cmd: string, cb: fun(ok:boolean, res:OsRunResult)): nil
---@field run_blocking fun(cmd: string): OsRunResult

return {}
