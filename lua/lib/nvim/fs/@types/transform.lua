---@meta
---@module 'lib.nvim.fs.@types.transform'

---@class Lib.Fs.Transform
---@field dedup fun(entries: string[]): string[]
---@field path_shorten fun(path: string, max_len: integer): string
---@field relpath fun(path: string, base: string): string

return {}


