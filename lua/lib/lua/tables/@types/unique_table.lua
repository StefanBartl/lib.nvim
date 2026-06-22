---@meta
---@module 'lib.lua.tables.@types.unique_table'

---@generic T
---@alias Lib.Tables.UniqueTable.List T[]

---@generic T
---@alias Lib.Tables.UniqueTable.KeyFn fun(value: T): any

---@class Lib.Tables.UniqueTable
---@field unique fun(list: Lib.Tables.UniqueTable.List<any>): Lib.Tables.UniqueTable.List<any> # Create a new list containing only unique elements from the input list. The first occurrence of each element is preserved.
---@field unique_by fun(list: Lib.Tables.UniqueTable.List<any>, key_fn: Lib.Tables.UniqueTable.KeyFn<any>): Lib.Tables.UniqueTable.List<any> # Create a new list containing only unique elements from the input list, using a custom key extraction function. This is useful when values are tables or when only part of a value should participate in the uniqueness decision.
---@field is_unique fun(list: Lib.Tables.UniqueTable.List<any>): boolean # Check whether a list already contains only unique elements.

return {}
