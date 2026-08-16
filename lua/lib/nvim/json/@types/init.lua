---@meta
---@module 'lib.nvim.json.@types'

---@class Lib.Nvim.Json
---@field decode fun(str: string): any, string|nil Decode a JSON string into a Lua value.
---@field encode fun(value: any, opts?: Lib.JSON.EncodeOpts): string|nil, string|nil JSON-encode a Lua value.

return {}
