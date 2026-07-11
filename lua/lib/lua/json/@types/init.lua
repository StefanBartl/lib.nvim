---@meta
---@module 'lib.lua.json.@types'

--- Decode namespace surface (`require("lib.lua.json").decode`).
---@class Lib.JSON.Decode
---@field to_string_array Lib.JSON.Decode.ToStringArray
---@field is_array_like fun(v: any): boolean
---@field ensure_string_array fun(v: any): string[]
---@field table_to_string_array fun(tbl: table): string[]

--- Aggregator surface of `require("lib.lua.json")`.
---@class Lib.JSON
---@field decode Lib.JSON.Decode
---@field encode Lib.JSON.Encode # Callable: `json.encode(value)`; also `json.encode.pretty(value)`.

return {}
