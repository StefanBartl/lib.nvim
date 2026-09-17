---@module 'lib.nvim.ui.hl'
--- Highlight helper utilities.
---
--- Idempotent highlight definition with namespace support.

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

  -- `Lib.Highlight.Opts` is the documented subset of
  -- `vim.api.keyset.highlight`: the same table, a different name.
  vim.api.nvim_set_hl(ns_id, group, opts --[[@as vim.api.keyset.highlight]])
end

--- Apply highlight state now and keep it correct across theme changes.
--- See `lib.nvim.ui.hl.persist` for the whole rationale; this is the entry
--- point callers use, so the helper sits on the same module as `set`.
---@param spec table<string, Lib.Highlight.Opts>|fun(): table<string, Lib.Highlight.Opts>|nil
---@param opts Lib.UI.HL.PersistOpts
---@return Lib.UI.HL.PersistHandle
function M.persist(spec, opts)
  return require("lib.nvim.ui.hl.persist").persist(spec, opts)
end

---@type Lib.UI.HL
return M
