---@module 'lib.lua.json'

local lazy = require("lib.lua.lazy")

local M = {}

-- =========================================================
-- Decode
-- =========================================================

---@type Lib.JSON.Decode.ToStringArray
local decode_to_str_arr_module = lazy.require("lib.lua.json.decode.to_string_array")

-- `M.decode` must be initialised before assigning fields onto it.
M.decode = {}
M.decode.to_string_array = decode_to_str_arr_module
M.decode.is_array_like = decode_to_str_arr_module.is_array_like
M.decode.ensure_string_array = decode_to_str_arr_module.ensure_string_array
M.decode.table_to_string_array = decode_to_str_arr_module.table_to_string_array

-- =========================================================
-- Encode
-- =========================================================

-- Callable module: `json.encode(value)` and `json.encode.pretty(value)`.
---@type Lib.JSON.Encode
M.encode = lazy.require("lib.lua.json.encode")

---@type Lib.JSON
return M
