---@meta
---@module 'lib.lua.tables.@types.safe'
-- =========================================================
-- Safe Table Operations
-- =========================================================

---@class Lib.Tables.Safe
---@field ensure_list fun(list: any[]|nil): any[] # Ensure value is a list. Returns input if it's a table, otherwise returns empty table.
---
---@field ensure_table fun(t: table|nil): table # Ensure value is a table. Returns input if it's a table, otherwise returns empty table.
---
---@field push fun(list: any[], v: any): integer # Push value to end of list. Mutates list. Returns new length.
---
---@field pop fun(list: any[]): any|nil # Remove and return last element of list. Mutates list. Returns nil if list is empty.
---
---@field insert_at fun(list: any[], idx: integer, v: any): boolean # Insert value at specific index. Mutates list. Returns true on success, false if index out of bounds [1..n+1].
---
---@field remove_at fun(list: any[], idx: integer): boolean # Remove element at specific index. Mutates list. Returns true on success, false if index out of bounds [1..n].
---
---@field snapshot_shallow fun(t: table): table # Create shallow snapshot of table. Useful for before/after comparisons or safe iteration during mutation.
---
---@field safe_ipairs fun(list: any[]): fun(): integer, any # Safe iterator over array. Captures length at start, preventing issues if list is mutated during iteration.

return {}
