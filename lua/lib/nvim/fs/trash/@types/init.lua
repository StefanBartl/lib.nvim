---@meta
---@module 'lib.nvim.fs.trash.@types'

---@class Lib.Fs.Trash
---@field trash fun(path: string, cb: fun(ok: boolean, err: string|nil)) Send `path` to the OS trash/recycle bin, asynchronously.
---@field trash_blocking fun(path: string): boolean, string|nil Send `path` to the OS trash/recycle bin, synchronously.

return {}
