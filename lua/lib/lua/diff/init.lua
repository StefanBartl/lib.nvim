---@module 'lib.lua.diff'
--- Aggregated export for line-diff helpers: `lines` (cheap splice-region
--- diff) and `myers` (full DP LCS-based edit script).

---@type LibDiff
local M = {}

M.lines = require("lib.lua.diff.lines")
M.myers = require("lib.lua.diff.myers")

return M
