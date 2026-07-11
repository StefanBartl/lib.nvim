---@meta
---@module 'lib.lua.json.encode.@types'

--- Options accepted by `lib.lua.json.encode`.
---@class Lib.JSON.EncodeOpts
---@field indent? integer|string # Pretty-print: number of spaces or a literal indent unit (e.g. "\t"). nil/0/"" = compact single-line output.
---@field sort_keys? boolean # Sort object keys for deterministic output (default true).

--- Pure-Lua JSON encoder module surface. The module table is callable:
--- `encode(value)` == `encode.encode(value)`.
---@class Lib.JSON.Encode
---@field encode fun(value: any, opts?: Lib.JSON.EncodeOpts): string|nil, string|nil # JSON string, or nil + error message.
---@field pretty fun(value: any, opts?: Lib.JSON.EncodeOpts): string|nil, string|nil # encode with indent = 2 by default.
---@overload fun(value: any, opts?: Lib.JSON.EncodeOpts): string|nil, string|nil

return {}
