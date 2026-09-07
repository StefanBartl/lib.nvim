---@meta
---@module 'lib.nvim.fs.ignore.list.@types'

---`require("lib.nvim.fs.ignore.list")` itself: canonical filesystem ignore
---rules + adapters for specific consumers (LuaLS, Telescope, Neo-tree).
---@class Lib.Fs.Ignore.List
---@field basenames string[]
---@field patterns string[]
---@field normalize fun(s: string): string
---@field as_set fun(): table<string, boolean>
---@field as_luals_patterns fun(): string[]
---@field as_telescope_patterns fun(): string[]
---@field as_neotree_names fun(): string[]

return {}
