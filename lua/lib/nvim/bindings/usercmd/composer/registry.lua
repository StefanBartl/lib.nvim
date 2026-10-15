---@module 'lib.nvim.bindings.usercmd.composer.registry'
--- Module-level registry of every verb built in this process (on `lib.nvim.registry`), plus the docs
--- configuration. Lets `composer.document()` emit the whole plugin's command surface in one call.

local M = {}

--- Every verb built in this process, in registration order (so generated docs are stable and predictable).
---@type Lib.Registry
local VERBS = require("lib.nvim.registry").new({ name = "composer.verbs" })

---@type Lib.UserCmd.Composer.DocsDefaults
M.docs = {
  path = "docs/BINDINGS/Usercmds.md",
  mode = "replace",
}

--- Register (or replace) a verb handle by command name.
---@param name string
---@param handle Lib.UserCmd.Composer.Handle
function M.add(name, handle)
  VERBS:register(name, handle)
end

--- Look up a registered verb handle by command name.
---@param name string
---@return Lib.UserCmd.Composer.Handle|nil
function M.get(name)
  return VERBS:get(name)
end

--- All handles in registration order.
---@return Lib.UserCmd.Composer.Handle[]
function M.all()
  return VERBS:all()
end

--- The full name→handle map (for `composer.registry()`).
---@return table<string, Lib.UserCmd.Composer.Handle>
function M.map()
  local out = {}
  for _, pair in ipairs(VERBS:entries()) do
    out[pair[1]] = pair[2]
  end
  return out
end

--- Apply setup() docs overrides.
---@param opts Lib.UserCmd.Composer.DocsOpts|nil
function M.configure(opts)
  if opts then
    M.docs = vim.tbl_extend("force", M.docs, opts) --[[@as Lib.UserCmd.Composer.DocsDefaults]]
  end
end

return M
