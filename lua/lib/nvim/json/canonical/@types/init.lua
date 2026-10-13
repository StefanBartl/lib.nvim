---@meta
---@module 'lib.nvim.json.canonical.@types'

---@class Lib.Json.CanonicalOpts
---@field indent? integer  Spaces per level: the readable form (golden files). Default: compact, the form that is hashed.

---@class Lib.Json.Canonical
---@field object fun(t?: table): table  Mark a table as a JSON object, even when it is empty.
---@field array fun(t?: table): table   Mark a table as a JSON array, even when it is empty.
---@field memo fun(t: table): table     Remember the compact text of a table that will not change.
---@field encode fun(value: any, opts?: Lib.Json.CanonicalOpts): string  Raises on a value JSON cannot hold; the message names the path.

return {}
