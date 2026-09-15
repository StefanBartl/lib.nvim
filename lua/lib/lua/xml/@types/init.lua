---@meta
---@module 'lib.lua.xml.@types'

--- A decoded XML element: `attrs` is a plain string-keyed map, `children` is
--- an ARRAY mixing nested `Lib.Xml.Element` tables and plain Lua strings
--- (text nodes). See `lib.lua.xml.decode`'s doc comment for why this stays a
--- plain tree instead of an attempt at a JSON-like object mapping.
---@class Lib.Xml.Element
---@field tag string
---@field attrs table<string, string>
---@field children (Lib.Xml.Element|string)[]

---@alias Lib.Xml.Decode fun(text: string): Lib.Xml.Element|nil, string|nil

--- `decode.lua`'s own module shape (a table with one `decode` field) --
--- distinct from `Lib.Xml.Decode` above, the bare function `lib.lua.xml`'s
--- aggregator re-exposes as `xml.decode`.
---@class Lib.Xml.DecodeModule
---@field decode Lib.Xml.Decode

--- Options accepted by `lib.lua.xml.encode`.
---@class Lib.Xml.EncodeOpts
---@field indent? integer # nil/0 = one compact line (default); N = multi-line, N spaces per level.

--- Pure-Lua XML encoder module surface. The module table is callable:
--- `encode(value)` == `encode.encode(value)`.
---@class Lib.Xml.Encode
---@field encode fun(value: any, opts?: Lib.Xml.EncodeOpts): string|nil, string|nil
---@field pretty fun(value: any, opts?: Lib.Xml.EncodeOpts): string|nil, string|nil # encode with indent = 2 by default.
---@overload fun(value: any, opts?: Lib.Xml.EncodeOpts): string|nil, string|nil

---@class LibXml
---@field decode fun(text: string): Lib.Xml.Element|nil, string|nil
---@field encode Lib.Xml.Encode
