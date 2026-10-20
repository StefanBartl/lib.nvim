---@module 'lib.config'
--- User-facing configuration for lib.nvim.
---
--- The only meaningful runtime choice is which aggregator strategy `require("lib")`
--- uses. All three resolve to the same public surface; they differ only in *when*
--- submodules are loaded:
---
---   - "metatable" (default) : per-key proxy, a submodule loads on first access.
---   - "lazy"                : eager key registry, submodules load on first access.
---   - "eager"               : every submodule is required up-front.
---
--- Direct module paths (e.g. `require("lib.nvim.notify")`) are unaffected by this
--- and are always the most efficient way to consume the library.
---
--- Configure BEFORE the first `require("lib")`:
---   require("lib.config").setup({ strategy = "lazy" })
---   local lib = require("lib")
---
--- Types: see @types/init.lua (Lib.Config.Options).

local M = {}

---@type Lib.Config.Options
local defaults = require("lib.config.DEFAULTS")

---@type table<string, string>
local STRATEGY_MODULES = {
  metatable = "lib.strategies.metatable",
  lazy = "lib.strategies.lazy",
  eager = "lib.strategies.eager",
}

---@param message string
local function warn(message)
  vim.notify("lib.config: " .. message, vim.log.levels.WARN)
end

local cfg = require("lib.lua.config").new(defaults, {
  name = "lib.config",
  schema = { strategy = { "string", enum = { "metatable", "lazy", "eager" } } },
  notify = warn,
  on_change = function(current, prev)
    -- The same table the options were always read from.
    M.options = current
    -- The aggregator is resolved once, on the first require("lib"). If that has
    -- already happened, a strategy change here silently has no effect -- warn so
    -- the call order can be fixed (setup() must run BEFORE require("lib")).
    local before = prev and prev.strategy or defaults.strategy
    if current.strategy ~= before and package.loaded["lib"] ~= nil then
      warn(
        (
          'strategy changed to %q after require("lib") already ran; '
          .. "this has no effect. Call lib.config.setup() before the first "
          .. 'require("lib").'
        ):format(current.strategy)
      )
    end
  end,
})

---The options in force: `Lib.Config.Options`, the same table `get()` returns.
---@type Lib.Config.Options
M.options = cfg.get()

---Set the options. Every call starts from the defaults, so an option left out
---of a second call is back at its default.
---
---An unknown key is reported before anything is merged and is not stored: a typo
---such as `startegy = "eager"` would otherwise land as a dead field while the
---default stays in force, and nothing would ever say so. A strategy that is not
---one of the three falls back to the default, with a warning.
---@param opts Lib.Config.Options|nil
function M.setup(opts)
  cfg.setup(opts)
end

---Returns the current (merged) configuration.
---@return Lib.Config.Options
function M.get()
  return cfg.get()
end

---Resolve the module path for the configured aggregator strategy.
---@return string
function M.strategy_module()
  return STRATEGY_MODULES[cfg.get("strategy")] or STRATEGY_MODULES.metatable
end

---@type Lib.Config
return M
