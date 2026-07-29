---@meta
---@module 'lib.nvim.cross.fs.lock.@types'

---One process holding an open handle on the queried path.
---@class Lib.Cross.Fs.Lock.Holder
---@field pid integer  Process id.
---@field name string  Process image name (e.g. `"nvim"`), or the Restart Manager's app name when the process has already exited.
---@field app string  Restart Manager's descriptive application name (e.g. `"PowerShell 7"`).

---@class Lib.Cross.Fs.Lock
---@field supported fun(): boolean
---@field probe fun(path: string): boolean, string|nil
---@field who fun(path: string, cb: fun(holders: Lib.Cross.Fs.Lock.Holder[]|nil, err: string|nil))
---@field report fun(path: string, cb: fun(lines: string[]))
