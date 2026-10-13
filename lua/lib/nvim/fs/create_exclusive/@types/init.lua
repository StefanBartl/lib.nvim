---@meta
---@module 'lib.nvim.fs.create_exclusive.@types'

---@class Lib.Fs.CreateExclusive
---@field EXISTS string                       The error answered when the file was already there (`"exists"`).
---@field is_exists fun(err: any): boolean    Whether an error is `EXISTS`.
---@overload fun(path: string, content: string): boolean, string|nil
local CreateExclusive = {}

return CreateExclusive
