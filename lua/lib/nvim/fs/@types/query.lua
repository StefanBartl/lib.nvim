---@meta
---@module 'lib.nvim.fs.@types.query'

---@class Lib.Fs.Query
---@field is_subpath fun(path: string, base: string): boolean
---@field is_dir fun(p: string): boolean
---@field find_upward_dir fun(names: string[], from: string): string|nil

return {}


