---@meta
---@module 'lib.lua.tables.@types.array'
-- =========================================================
-- Array Operations
-- =========================================================

---@class Lib.Tables.Array
---@field len fun(xs: any[]): integer # Return length using # operator (assumes dense array).
---
---@field clone fun(xs: any[]): any[] # Create a shallow copy of a dense array with preallocation.
---
---@field map fun(xs: any[], f: fun(v: any, i: integer, xs: any[]): any): any[] # Map over a dense array with preallocation. Returns new array with transformed values.
---
---@field filter fun(xs: any[], pred: fun(v: any, i: integer, xs: any[]): boolean): any[] # Filter a dense array. Prealloc then compact in one pass. Returns new array with elements matching predicate.
---
---@field reduce fun(xs: any[], f: fun(acc: any, v: any, i: integer): any, init: any): any # Reduce with explicit initial accumulator. Iterates left-to-right.
---
---@field partition fun(xs: any[], pred: fun(v: any, i: integer, xs: any[]): boolean): any[], any[] # Partition into {pass, fail} according to predicate. Returns two arrays: passing elements and failing elements.
---
---@field flatten fun(xss: any[][]): any[] # Flatten one level of nested arrays. Preallocates based on total size.
---
---@field unique fun(xs: any[]): any[] # Unique by equality (O(n) with set if primitives). Preserves first occurrence order.
---
---@field pluck fun(xs: table[], key: string): any[] # Pluck a field from array of tables, skipping nils. Returns array of extracted values.
---
---@field sorted fun(xs: any[], cmp: fun(a: any, b: any): boolean): any[] # Sort copy (stable-ish for small arrays); does not mutate input. Uses table.sort internally.

return {}
