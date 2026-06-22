---@meta
---@module 'lib.lua.tables.@types.functional'
-- =========================================================
-- Functional Programming Utilities
-- =========================================================

---@class Lib.Tables.Functional
---@field map fun(list: any[], fn: fun(item: any, index: integer): any): any[] # Map function over array. Returns new array with transformed elements. Pure function.
---
---@field filter fun(list: any[], pred: fun(item: any, index: integer): boolean): any[] # Filter array by predicate. Returns new array containing only elements matching predicate. Pure function.
---
---@field reduce fun(list: any[], init: any, fn: fun(acc: any, item: any, index: integer): any): any # Reduce array to single value. Starts with init accumulator and applies fn left-to-right.
---
---@field find fun(list: any[], pred: fun(item: any, index: integer): boolean): any|nil # Find first element matching predicate. Returns element or nil if not found.
---
---@field any fun(list: any[], pred: fun(item: any): boolean): boolean # Check if any element matches predicate. Short-circuits on first match.
---
---@field all fun(list: any[], pred: fun(item: any): boolean): boolean # Check if all elements match predicate. Short-circuits on first non-match.
---
---@field flat_map fun(list: any[], fn: fun(item: any): any[]): any[] # Map and flatten in one pass. Applies fn to each element (fn must return array) and concatenates results.

return {}
