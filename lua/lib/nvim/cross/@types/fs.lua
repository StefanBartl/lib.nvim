---@meta
---@module 'lib.nvim.cross.@types.fs'

---@class Lib.Cross.Fs
---@field cwd fun(): string

---@class Lib.Cross.Separators
---@field has_win_sep fun(s: string): boolean
---@field normalize fun(path: string): string|nil
---@field unify_slashes fun(path: string): string
---@field collapse_dots fun(path: string): string

return {}
