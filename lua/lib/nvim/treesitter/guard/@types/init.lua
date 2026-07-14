---@meta
---@module 'lib.nvim.treesitter.guard.@types'

---@class Lib.Treesitter.Guard
---@field DEFAULT_WHITELIST table<string, boolean>
---@field is_enabled fun(bufnr: integer, whitelist?: table<string, boolean>): boolean
