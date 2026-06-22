---@module 'lib.lua.tables.unique_table'
--- Utilities for creating stable, order-preserving unique tables.
---
--- This module provides helpers to deduplicate sequence-like tables while
--- preserving insertion order. It is intentionally generic and can be reused
--- across unrelated subsystems (patterns, keywords, buffers, paths, etc.).

local M = {}


-- =========================================================
-- Core functionality
-- =========================================================

--- Create a new list containing only unique elements from the input list.
--- The first occurrence of each element is preserved.
---
--- Uniqueness is determined using Lua's `==` operator.
---
---@generic T
---@param list Lib.Tables.UniqueTable.List<T>
---@return Lib.Tables.UniqueTable.List<T>
function M.unique(list)
  ---@type table<any, true>
  local seen = {}

  local result = {}

  for _, value in ipairs(list) do
    if not seen[value] then
      seen[value] = true
      result[#result + 1] = value
    end
  end

  return result
end

--- Create a new list containing only unique elements from the input list,
--- using a custom key extraction function.
---
--- This is useful when values are tables or when only part of a value should
--- participate in the uniqueness decision.
---
---@generic T
---@param list Lib.Tables.UniqueTable.List<T>
---@param key_fn Lib.Tables.UniqueTable.KeyFn<T>
---@return Lib.Tables.UniqueTable.List<T>
function M.unique_by(list, key_fn)
  ---@type table<any, true>
  local seen = {}

  local result = {}

  for _, value in ipairs(list) do
    local key = key_fn(value)
    if not seen[key] then
      seen[key] = true
      result[#result + 1] = value
    end
  end

  return result
end

--- Check whether a list already contains only unique elements.
---
---@generic T
---@param list Lib.Tables.UniqueTable.List<T>
---@return boolean
function M.is_unique(list)
  ---@type table<any, true>
  local seen = {}

  for _, value in ipairs(list) do
    if seen[value] then
      return false
    end
    seen[value] = true
  end

  return true
end

---@type Lib.Tables.UniqueTable
return M
