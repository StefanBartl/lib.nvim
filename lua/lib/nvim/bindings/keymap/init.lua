---@module 'lib.nvim.bindings.keymap'
--- Keymaps: the one-off wrapper, and the named-action registry.
---@description
--- Two levels, and most plugins want both:
---
--- **`keymap(...)`** -- the validated `vim.keymap.set` wrapper this module has
--- always been. For the mappings that are not part of a plugin's public
--- surface: buffer-local keys inside a floating window, `q` to close a report,
--- anything a user has no reason to rebind.
---
--- ```lua
--- local keymap = require("lib.nvim.bindings.keymap")
--- keymap("n", "q", close, { buffer = true }, "close")
--- ```
---
--- **`keymap.register(...)`** -- named actions the user's spec can remap or
--- switch off, one by one. For everything that *is* public surface. See
--- `registry.lua` for the shape and for why the override table is keyed by
--- action name rather than by the current `lhs`.
---
--- ```lua
--- keymap.register("spotlight", {
---   prefix = "<leader>s",
---   which_key = { group = "Spotlight" },
---   actions = {
---     toggle = { default = "<leader>sK", rhs = api.toggle, desc = "toggle every occurrence" },
---   },
--- }, cfg.keymaps)
--- ```
---
--- The module stays **callable** so that the first form keeps working
--- unchanged: it is `require`d in over a hundred places across these plugins,
--- and turning it into a plain table would have broken every one of them for
--- no benefit.
---@see lib.nvim.bindings.keymap.registry
---@see lib.nvim.bindings.keymap.which_key

local set = require("lib.nvim.bindings.keymap.set")

local M = {}

--- Set one keymap. Identical to calling the module itself.
---@type fun(modes: string|string[], lhs: string, rhs: string|function, opts: Lib.Map.Opts|nil, desc: string?): nil
M.set = set

--- Register a plugin's named actions. See `registry.register`.
---@param plugin string
---@param spec Lib.Keymap.Spec
---@param user table|false|nil
---@return Lib.Keymap.Registered[]
function M.register(plugin, spec, user)
  return require("lib.nvim.bindings.keymap.registry").register(plugin, spec, user)
end

--- Everything registered so far. See `registry.registered`.
---@param plugin string|nil
---@return table<string, Lib.Keymap.Registered[]>|Lib.Keymap.Registered[]
function M.registered(plugin)
  return require("lib.nvim.bindings.keymap.registry").registered(plugin)
end

--- `lhs` values claimed by more than one plugin. See `registry.conflicts`.
---@return Lib.Keymap.Conflict[]
function M.conflicts()
  return require("lib.nvim.bindings.keymap.registry").conflicts()
end

---@type Lib.Keymap
return setmetatable(M, {
  __call = function(_, modes, lhs, rhs, opts, desc)
    return set(modes, lhs, rhs, opts, desc)
  end,
})
