---@module 'lib.nvim.deps.first_run'
--- Show a plugin's declared-tools popup exactly once, ever, persisted across
--- Neovim restarts — for the "I just installed this plugin via lazy.nvim,
--- restarted, and the first time it initializes I want to be told what CLI
--- tools it wants and why" flow, instead of reading the README and copying
--- install commands by hand.
---
--- The trigger is deliberately `M.show_once`, called from the *consuming
--- plugin's own* `setup()` — never from `require`. That keeps the rule the
--- rest of `lib.nvim.deps` already holds to: requiring a module here never
--- touches the user's editor by itself. A plugin opts in with one line:
---
---   function M.setup(opts)
---     ...
---     require("lib.nvim.deps").show_once("pdfport.nvim")
---   end
---
--- After the first run, `:Lib deps show pdfport.nvim` is the ongoing way to
--- see the same report — `show_once` does not run again.
---
--- User-side opt-out, checked on every `show_once` call — set from the
--- user's own `init.lua`, no `require("lib.nvim.deps").setup()` call
--- needed (so it works regardless of load order relative to the plugins
--- that call `show_once`):
---
---   vim.g.lib_nvim_deps_disable_first_run = true        -- every plugin
---   vim.g.lib_nvim_deps_disabled_plugins = { "images.nvim" }  -- just these

local NAMESPACE = "lib.nvim.deps.first_run"

local M = {}

---@internal
---@param cache_opts Lib.Cache.Opts|nil
---@return table<string, boolean>
local function load_seen(cache_opts)
  local disk = require("lib.nvim.cache.disk")
  return disk.load(NAMESPACE, cache_opts) or {}
end

---True when `show_once` has already run for `plugin_name` (in this or an
---earlier session).
---@param plugin_name string
---@param cache_opts? Lib.Cache.Opts
---@return boolean
function M.seen(plugin_name, cache_opts)
  return load_seen(cache_opts)[plugin_name] == true
end

---Record `plugin_name` as seen, persisted to disk immediately.
---@param plugin_name string
---@param cache_opts? Lib.Cache.Opts
function M.mark_seen(plugin_name, cache_opts)
  local disk = require("lib.nvim.cache.disk")
  local seen = load_seen(cache_opts)
  seen[plugin_name] = true
  disk.save(NAMESPACE, seen, cache_opts)
end

---Forget `plugin_name` (or, with no argument, every plugin) — the popup
---will show again on the next `show_once` call. Exists for `:Lib deps
---reset-first-run` and tests; not expected to be reached in normal use.
---@param plugin_name? string
---@param cache_opts? Lib.Cache.Opts
function M.reset(plugin_name, cache_opts)
  local disk = require("lib.nvim.cache.disk")
  if not plugin_name then
    disk.clear(NAMESPACE, cache_opts)
    return
  end
  local seen = load_seen(cache_opts)
  seen[plugin_name] = nil
  disk.save(NAMESPACE, seen, cache_opts)
end

---@internal
---True when the user has opted out of first-run popups, globally or for
---this specific plugin, via `vim.g`. Checked fresh on every call (not
---cached) — these are meant to be set once in the user's own config and
---read as plain globals, not toggled at runtime.
---@param plugin_name string
---@return boolean
local function user_disabled(plugin_name)
  if vim.g.lib_nvim_deps_disable_first_run then
    return true
  end
  local disabled_list = vim.g.lib_nvim_deps_disabled_plugins
  if type(disabled_list) == "table" then
    for _, name in ipairs(disabled_list) do
      if name == plugin_name then
        return true
      end
    end
  end
  return false
end

---Show `plugin_name`'s declared-tools popup once, ever. No-op on every call
---after the first — including when there was nothing to show (no spec
---file, spec declares no tools, or nothing declared is actually missing):
---each of those still marks it seen, so a plugin with no missing tools
---doesn't get silently re-checked (and potentially popped up) on every
---subsequent startup once one *becomes* missing later — this is a one-time
---welcome, not an ongoing watcher. `:Lib deps show` stays available for
---checking again at any time.
---
---Also a no-op, without marking anything seen, when the user opted out via
---`vim.g.lib_nvim_deps_disable_first_run` or
---`vim.g.lib_nvim_deps_disabled_plugins` — not marking it seen means the
---popup picks up right where it would have if the user later removes the
---opt-out, rather than having been silently consumed while disabled.
---@param plugin_name string
---@param opts? { manager?: Lib.Deps.Manager, cache?: Lib.Cache.Opts }
---@return boolean shown
function M.show_once(plugin_name, opts)
  opts = opts or {}
  if user_disabled(plugin_name) then
    return false
  end
  if M.seen(plugin_name, opts.cache) then
    return false
  end

  local spec = require("lib.nvim.deps.spec")
  local path = spec.find(plugin_name)
  if not path then
    M.mark_seen(plugin_name, opts.cache)
    return false
  end

  local result = spec.load(path)
  if not result or #result.tools == 0 then
    M.mark_seen(plugin_name, opts.cache)
    return false
  end

  local install = require("lib.nvim.deps.install")
  local plan = install.plan(result.tools, { manager = opts.manager })
  M.mark_seen(plugin_name, opts.cache)

  if #plan.missing == 0 then
    return false
  end

  require("lib.nvim.deps.view").show(plugin_name, result, { manager = opts.manager })
  return true
end

---@type Lib.Deps.FirstRun
return M
