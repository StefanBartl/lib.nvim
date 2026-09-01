---@module 'lib.nvim_usrcmds'
--- Utility user commands that don't belong in a more specific plugin.
--- Each command is opt-in and can be toggled independently in `setup()`.
---
--- This is lib.nvim's whole binding surface, and it is split the way every
--- plugin in this ecosystem splits its `bindings/` folder -- one module per
--- kind, so "what does this install" is a lookup rather than a grep:
---
---   * `lib.nvim_usrcmds.actions`  -- the command bodies, shared by both surfaces
---   * `lib.nvim_usrcmds.usrcmds`  -- `:CwdHere`, `:PowershellProfile`, `:Lib`
---   * `lib.nvim_usrcmds.autocmds` -- the post-`:Lazy sync` helptags hook
---
--- No keymaps module: a library that other plugins depend on has no business
--- claiming a key on their behalf, and this namespace sets none.

require("lib.nvim_usrcmds.@types")

local M = {}

---@type Lib.NvimUsrCmds.Options
local defaults = {
  helptags = true,
  cwd_here = true,
  powershell_profile = vim.fn.has("win32") == 1,
  lib_verb = true,
  deps = true,
}

---Sets up the opt-in utility user commands per `opts`.
---@param opts Lib.NvimUsrCmds.Options|nil
---@return nil
function M.setup(opts)
  local o = vim.tbl_extend("force", defaults, opts or {})
  local usrcmds = require("lib.nvim_usrcmds.usrcmds")

  if o.helptags then
    require("lib.nvim_usrcmds.autocmds").helptags()
  end
  if o.cwd_here then
    usrcmds.cwd_here()
  end
  if o.powershell_profile then
    usrcmds.powershell_profile()
  end
  if o.lib_verb then
    usrcmds.lib_verb(o)
  end
end

return M
