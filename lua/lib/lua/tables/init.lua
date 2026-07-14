---@module 'lib.lua.tables'
--- Aggregated export for table helpers.

local lazy = require("lib.lua.lazy")

local M = {}

-- =========================================================
-- Array Operations
-- =========================================================

---@type Lib.Tables.Array
local array_module = lazy.require("lib.lua.tables.array")

M.len = array_module.len
M.clone = array_module.clone
M.map = array_module.map
M.filter = array_module.filter
M.reduce = array_module.reduce
M.partition = array_module.partition
M.flatten = array_module.flatten
M.unique = array_module.unique
M.pluck = array_module.pluck
M.sorted = array_module.sorted

-- =========================================================
-- Core Table Utilities
-- =========================================================

---@type Lib.Tables.Core
local core_module = lazy.require("lib.lua.tables.core")

M.is_table = core_module.is_table
M.is_array = core_module.is_array
M.shallow_copy = core_module.shallow_copy
M.deep_copy = core_module.deep_copy
M.keys = core_module.keys
M.values = core_module.values
M.invert_set = core_module.invert_set
M.pick = core_module.pick
M.omit = core_module.omit
M.merge_shallow = core_module.merge_shallow
M.merge_deep = core_module.merge_deep
M.dedup_list = core_module.dedup_list
M.dedup_indices = core_module.dedup_indices
M.slice = core_module.slice
M.unique_push = core_module.unique_push
M.binary_search = core_module.binary_search
M.group_by = core_module.group_by
M.count_by = core_module.count_by

-- =========================================================
-- Dictionary Operations
-- =========================================================

---@type Lib.Tables.Dict
local dict_module = lazy.require("lib.lua.tables.dict")

M.dict_clone = dict_module.clone
M.dict_pick = dict_module.pick
M.dict_omit = dict_module.omit
M.dict_merge = dict_module.merge
M.dict_keys = dict_module.keys
M.dict_values = dict_module.values
M.dict_group_by = dict_module.group_by

-- =========================================================
-- Set Operations
-- =========================================================

---@type Lib.Tables.Set
local set_module = lazy.require("lib.lua.tables.set")

M.from_array = set_module.from_array
M.to_array = set_module.to_array
M.add = set_module.add
M.add_all = set_module.add_all
M.remove = set_module.remove
M.remove_all = set_module.remove_all
M.clear = set_module.clear
M.has = set_module.has
M.size = set_module.size
M.copy = set_module.copy
M.from_keys = set_module.from_keys
M.union = set_module.union
M.intersection = set_module.intersection
M.difference = set_module.difference
M.symmetric_difference = set_module.symmetric_difference
M.is_subset = set_module.is_subset
M.is_superset = set_module.is_superset
M.equals = set_module.equals
M.set_filter = set_module.filter
M.set_map = set_module.map
M.iter = set_module.iter

-- =========================================================
-- Safe Table Operations
-- =========================================================

---@type Lib.Tables.Safe
local safe_module = lazy.require("lib.lua.tables.safe")

M.ensure_list = safe_module.ensure_list
M.ensure_table = safe_module.ensure_table
M.push = safe_module.push
M.pop = safe_module.pop
M.insert_at = safe_module.insert_at
M.remove_at = safe_module.remove_at
M.snapshot_shallow = safe_module.snapshot_shallow
M.safe_ipairs = safe_module.safe_ipairs

---@type Lib.Tables
return M

