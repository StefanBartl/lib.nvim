---@meta
---@module 'lib.lua.json.decode.@types'

---@class Lib.JSON.Decode.ToStringArray
---@description
--- Flattens whatever a JSON decode produced into a `string[]`.
--- The adapter between free-form JSON data (string, table, scalar) and
--- downstream APIs that want a strict `string[]` -- a UI list, for instance.
---
---@field is_array_like fun(v: any): boolean
--- Whether a value is an array-like table: contiguous positive integer keys
--- starting at 1, which is Lua's own array semantics. Maps, sparse arrays and
--- non-tables are false.
---
---@field table_to_string_array fun(tbl: table): string[]
--- Convert a table into a `string[]`.
--- * Array-like tables: every element goes through `tostring`.
--- * Everything else: keys are sorted stably and serialized as
---   `"key: value"` strings, so the output does not depend on `pairs` order.
--- * Nested tables are rendered with `vim.inspect`.
---
---@field ensure_string_array fun(v: any): string[]
--- Coerce any input into a `string[]`.
--- * table   -> `table_to_string_array`
--- * string  -> split on newlines (`vim.split`)
--- * scalar  -> a one-element array holding `tostring(v)`
--- Never returns nil.

return {}
