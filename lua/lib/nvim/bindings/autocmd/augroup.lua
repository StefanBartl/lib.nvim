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
--- drops are forgotten too (see `autocmd.forget_group`), and the id is known to
--- the autocmd module by its name: an autocmd created with this id is recorded
--- under the group, so the next clear can forget it (a record without a group
--- name is never forgotten, and the registry grew with every `setup()`).
---@param name string
---@return integer
function M.create.clear(name)
  return require("lib.nvim.bindings.autocmd").get_augroup(name, { clear = true })
end

---@type Lib.AutoCmd.AuGroup
return M
