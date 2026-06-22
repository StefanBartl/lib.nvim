---@module 'lib.nvim.core'

local lazy = require("lib.lua.lazy")

local M = {}

---@param bin string
---@return boolean
function M.has_exec(bin)
  return vim.fn.executable(bin) == 1
end

M.simple_echo = lazy.require("lib.nvim.core.simple_echo")

---@type Lib.Nvim
return M
