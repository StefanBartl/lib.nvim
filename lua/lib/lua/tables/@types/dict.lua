---@meta
---@module 'lib.lua.tables.@types.dict'
-- =========================================================
-- Dictionary Operations
-- =========================================================

---@class Lib.Tables.Dict
---@field clone fun(t: table): table # Shallow copy of a dictionary. Copies all key-value pairs.
---
---@field pick fun(t: table, keys: any[]): table # Pick subset of keys from dictionary. Returns new table with only specified keys (if they exist in source).
---
---@field omit fun(t: table, keys: any[]): table # Omit specified keys from dictionary. Returns new table excluding specified keys.
---
---@field merge fun(a: table, b: table): table # Merge two dictionaries (right-biased). Returns new table with b's values overwriting a's for shared keys.
---
---@field keys fun(t: table): any[] # Extract all keys as array. Preallocates output array for performance.
---
---@field values fun(t: table): any[] # Extract all values as array. Preallocates output array for performance.
---
---@field group_by fun(xs: any[], keyfn: fun(v: any): string|number): table<string|number, any[]> # Group array of items into dict of arrays by key function. Returns table mapping keys to arrays of items with that key.

return {}
