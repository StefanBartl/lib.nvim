---@meta
---@module 'lib.lua.yaml.@types'

--- Options accepted by `lib.lua.yaml.encode`.
---@class Lib.Yaml.EncodeOpts
---@field indent? integer # Spaces per nesting level (default 2). YAML has no compact/pretty distinction the way JSON does -- this is the encoder's only style knob.

--- Pure-Lua YAML encoder module surface. The module table is callable:
--- `encode(value)` == `encode.encode(value)`.
---@class Lib.Yaml.Encode
---@field encode fun(value: any, opts?: Lib.Yaml.EncodeOpts): string|nil, string|nil # YAML text, or nil + error message.
---@field pretty fun(value: any, opts?: Lib.Yaml.EncodeOpts): string|nil, string|nil # Alias for `encode` (kept for API symmetry with lib.lua.json.encode.pretty).
---@overload fun(value: any, opts?: Lib.Yaml.EncodeOpts): string|nil, string|nil

---@class LibYaml
---@field simple_parse fun(text: string): table|nil, string|nil # Decode a minimal YAML-ish subset into a nested Lua table, or nil + err message on malformed indentation.
---@field encode Lib.Yaml.Encode # Pure-Lua encoder, the counterpart to simple_parse (see lib.lua.yaml.encode's own doc comment for the exact subset covered).
