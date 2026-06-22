---@module 'lib.lua.strings.transform'
--- Aggregated string transformation helpers.

local M = {}

-- simple transforms
M.remove_prefix = require("lib.lua.strings.remove_prefix")

-- core transforms
local core = require("lib.lua.strings.core")

M.trim = core.trim
M.slugify = core.slugify
M.kebab_case = core.kebab_case
M.snake_case = core.snake_case
M.camel_case = core.camel_case
M.capitalize = core.capitalize
M.uncapitalize = core.uncapitalize
M.normalize_ws = core.normalize_ws
M.pad_start = core.pad_start
M.pad_end = core.pad_end
M.pad_center = core.pad_center
M.indent = core.indent
M.dedent = core.dedent

return M

