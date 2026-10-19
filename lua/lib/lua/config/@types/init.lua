---@meta
---@module 'lib.lua.config.@types'

---@class Lib.Config
---@field copy fun(t: any, seen?: table<table, table>): any
---@field deep_merge fun(base: table, override: table): table
---@field get fun(tbl: table, path: string?): any

return {}
