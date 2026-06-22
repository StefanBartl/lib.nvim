---@module 'lib.nvim.ui.hl'
-- =========================================================
-- Highlight helper utilities.
--
-- Idempotent highlight definition with namespace support.
-- =========================================================

local M = {}

---@type table<string, integer>
local namespaces = {}

---@param name string
---@return integer
function M.namespace(name)
  if namespaces[name] == nil then
    namespaces[name] = vim.api.nvim_create_namespace(name)
  end
  return namespaces[name]
end

---@param group string
---@param opts Lib.Highlight.Opts
---@param ns string|integer|nil
function M.set(group, opts, ns)
  local ns_id = 0
  if type(ns) == "string" then
    ns_id = M.namespace(ns)
  elseif type(ns) == "number" then
    ns_id = ns
  end

  vim.api.nvim_set_hl(ns_id, group, opts)
end

---@type Lib.UI.HL
return M

