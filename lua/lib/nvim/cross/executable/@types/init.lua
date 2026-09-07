---@meta
---@module 'lib.nvim.cross.executable.@types'

---`require("lib.nvim.cross.executable")` itself: PATH resolution + Mason
---binary lookup, memoized per name.
---@class Lib.Cross.Executable
---@field exists fun(name: string): boolean
---@field path fun(name: string): string|nil
---@field find fun(name_or_candidates: string|string[]): string|nil
---@field mason_bin fun(package_name: string): string|nil
---@field clear fun(name?: string): nil

return {}
