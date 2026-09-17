---@module 'lib.nvim.ui.hl.persist'
--- Keep highlight state correct across theme changes.
---
--- A `:colorscheme` clears every user-defined highlight group and rebuilds
--- the built-in ones from scratch. Anything a plugin defined, derived or
--- cached from those colours is stale the moment it runs. The remedy is
--- always the same four lines -- apply now, register a `ColorScheme`
--- autocmd in an augroup, give it a description, apply again -- and across
--- this fleet it had been written out by hand **19 times in 7 plugins**.
---
--- Hand-written is not the problem; hand-written *differently* is. The
--- survey behind this module (`nvim/docs/ROADMAP/reports/ui-my-Kreuzfeature-Analyse.md`,
--- finding C1) found three real divergences between otherwise identical
--- blocks:
---
---   * **`OptionSet background` was almost always missing.** Switching
---     `&background` selects the other half of a light/dark palette without
---     necessarily firing `ColorScheme`. `spotlight.nvim` handled it;
---     nobody else did. It is on by default here.
---   * **Some sites never re-applied at all.** `ui.nvim`'s diagnostic
---     virtual-text tweak was applied exactly once at setup, so the first
---     theme switch undid it permanently -- including the switches that
---     plugin fires itself.
---   * **Some applied but never re-applied immediately**, leaving the first
---     paint to whatever event happened to come next.
---
--- The callback decides what "apply" means. Redefining groups and clearing
--- a colour-derived cache are the same problem shaped differently, and both
--- belong here: of the 19 sites, 4 were cache invalidation.
---
---   local hl = require("lib.nvim.ui.hl")
---
---   -- static groups
---   hl.persist({
---     DiagnosticVirtualTextError = { bg = "NONE" },
---   }, { name = "myplugin_diagnostics" })
---
---   -- groups derived from the active theme
---   hl.persist(function()
---     local fg = vim.api.nvim_get_hl(0, { name = "Comment" }).fg
---     return { MyDim = { fg = fg } }
---   end, { name = "myplugin_dim" })
---
---   -- no groups at all: drop a cache keyed on theme colours
---   local handle = hl.persist(function()
---     cache = {}
---   end, { name = "myplugin_cache" })
---   handle.detach()

require("lib.nvim.ui.hl.@types")

local autocmd = require("lib.nvim.bindings.autocmd")

local M = {}

--- Resolve `spec` into the group table to apply, or nil when the callback
--- did the work itself.
---@param spec table<string, Lib.Highlight.Opts>|fun(): table<string, Lib.Highlight.Opts>|nil
---@return table<string, Lib.Highlight.Opts>|nil
local function resolve(spec)
  if type(spec) == "function" then
    local out = spec()
    if type(out) == "table" then
      return out
    end
    -- A function returning nothing is a side-effect callback (a cache
    -- clear, a refresh). That is a supported shape, not a mistake.
    return nil
  end
  return spec
end

--- Apply `spec` now, and again after every theme change.
---
--- Idempotent in the way that matters: the augroup is cleared on create, so
--- calling this twice with the same `name` replaces the autocommands rather
--- than stacking a second set. Re-running it is how a caller rebinds after
--- a config change.
---
--- Errors inside the callback are caught. A broken highlight definition
--- must not take down the `ColorScheme` event for every other listener --
--- which, before this existed, is exactly what an unguarded hand-written
--- block could do.
---@param spec table<string, Lib.Highlight.Opts>|fun(): table<string, Lib.Highlight.Opts>|nil
---@param opts Lib.UI.HL.PersistOpts
---@return Lib.UI.HL.PersistHandle
function M.persist(spec, opts)
  vim.validate("opts", opts, "table")
  vim.validate("opts.name", opts.name, "string")

  local hl = require("lib.nvim.ui.hl")
  local ns = opts.ns
  local background = opts.background ~= false

  local function apply()
    local defs = resolve(spec)
    if not defs then
      return
    end
    for group, def in pairs(defs) do
      hl.set(group, def, ns)
    end
  end

  local function apply_guarded()
    local ok, err = pcall(apply)
    if not ok then
      require("lib.nvim.notify")
        .create("[lib.nvim.ui.hl.persist]")
        .warn(("%s: %s"):format(opts.name, tostring(err)))
    end
  end

  local group = autocmd.group(opts.name, true)

  autocmd.create("ColorScheme", apply_guarded, {
    group = group,
    pattern = "*",
    desc = ("%s: re-apply after a colorscheme change"):format(opts.name),
  })

  if background then
    -- Not redundant with ColorScheme. Switching `&background` is what
    -- selects the other half of a light/dark palette, and it does not
    -- always re-source the colorscheme.
    autocmd.create("OptionSet", apply_guarded, {
      group = group,
      pattern = "background",
      desc = ("%s: re-apply after a background change"):format(opts.name),
    })
  end

  if opts.immediate ~= false then
    apply_guarded()
  end

  return {
    apply = apply_guarded,
    detach = function()
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  }
end

return M
