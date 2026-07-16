---@module 'lib.lua.numeral'
--- Aggregated export for numeral conversion helpers: `roman` and `alpha`.

---@type LibNumeral
local M = {}

M.roman = require("lib.lua.numeral.roman")
M.alpha = require("lib.lua.numeral.alpha")

return M
