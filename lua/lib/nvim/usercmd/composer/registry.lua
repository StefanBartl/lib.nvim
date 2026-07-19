---@module 'lib.nvim.usercmd.composer.registry'
--- Module-level registry of every verb built in this process, plus the docs
--- configuration. Lets `composer.document()` emit the whole plugin's command
--- surface in one call.

local M = {}

---@type table<string, Lib.UserCmd.Composer.Handle>
local VERBS = {}

--- Insertion order, so generated docs are stable and predictable.
---@type string[]
local ORDER = {}

---@type Lib.UserCmd.Composer.DocsOpts
M.docs = {
  path = "docs/BINDINGS/Usercmds.md",
  mode = "replace",
}

--- Register (or replace) a verb handle by command name.
---@param name string
---@param handle Lib.UserCmd.Composer.Handle
function M.add(name, handle)
  if VERBS[name] == nil then
    ORDER[#ORDER + 1] = name
  end
  VERBS[name] = handle
end

---@param name string
---@return Lib.UserCmd.Composer.Handle|nil
function M.get(name)
  return VERBS[name]
end

--- All handles in registration order.
---@return Lib.UserCmd.Composer.Handle[]
function M.all()
  local out = {}
  for _, name in ipairs(ORDER) do
    out[#out + 1] = VERBS[name]
  end
  return out
end

--- The full name→handle map (for `composer.registry()`).
---@return table<string, Lib.UserCmd.Composer.Handle>
function M.map()
  return vim.tbl_extend("force", {}, VERBS)
end

--- Apply setup() docs overrides.
---@param opts Lib.UserCmd.Composer.DocsOpts|nil
function M.configure(opts)
  if opts then
    M.docs = vim.tbl_extend("force", M.docs, opts)
  end
end

return M
