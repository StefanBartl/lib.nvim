---@module 'lib.nvim.autocmd.augroup'
-- =========================================================
    -- Augroup registry.
--
-- Centralized augroup creation with optional prefixing
-- and deduplication.
-- =========================================================

local M = {
  create = {}
}

--- Create/clear a namespaced augroup.
---@param name string
---@return integer
function M.create.clear(name)
  return vim.api.nvim_create_augroup(name, { clear = true })
end

---@type Lib.AutoCmd.AuGroup
return M

