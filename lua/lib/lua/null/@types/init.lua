---@meta
---@module 'lib.lua.null.@types'

---@class Lib.Lua.Null
---@field NULL table                       # The shared null sentinel (identity-compared).
---@field is_null fun(v: any): boolean     # Whether `v` is the shared null sentinel.
