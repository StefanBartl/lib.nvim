---@module 'lib.lua.numeral'
--- Aggregated export for numeral conversion helpers: `roman` and `alpha`.

---@type LibNumeral
local M = {
  roman = require("lib.lua.numeral.roman"),
  alpha = require("lib.lua.numeral.alpha"),
}

return M
