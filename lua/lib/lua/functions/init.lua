---@module 'lib.lua.functions'

local lazy = require("lib.lua.lazy")
---@type Lib.Functions.Meta
local meta = lazy.require("lib.lua.functions.meta")

local M = {}

M.noop = meta.noop
M.identity = meta.identity
M.always_true = meta.always_true
M.always_false = meta.always_false
M.const = meta.const
M.raise  = meta.raise

---@type Lib.Functions
return M

