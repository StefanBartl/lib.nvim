---@module 'lib.nvim.bindings.autocmd.augroup'
-- =========================================================
-- Augroup registry.
--
-- Centralized augroup creation with optional prefixing
-- and deduplication.
-- =========================================================

local M = {
  create = {},
}

--- Create/clear a namespaced augroup. The records of the autocmds the clear
--- drops are forgotten too (see `autocmd.forget_group`).
---@param name string
---@return integer
function M.create.clear(name)
  require("lib.nvim.bindings.autocmd").forget_group(name)
  return vim.api.nvim_create_augroup(name, { clear = true })
end

---@type Lib.AutoCmd.AuGroup
return M
