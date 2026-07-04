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

---@type Lib.Config.Options
M.options = vim.deepcopy(defaults)

---Merge user options.
---@param opts Lib.Config.Options|nil
function M.setup(opts)
  local prev = M.options.strategy
  M.options = vim.tbl_extend("force", M.options, opts or {})

  if not STRATEGY_MODULES[M.options.strategy] then
    vim.notify(
      ("lib.config: unknown strategy %q, falling back to 'metatable'"):format(
        tostring(M.options.strategy)
      ),
      vim.log.levels.WARN
    )
    M.options.strategy = "metatable"
  end

  -- The aggregator is resolved once, on the first require("lib"). If that has
  -- already happened, a strategy change here silently has no effect — warn so
  -- the call order can be fixed (setup() must run BEFORE require("lib")).
  if M.options.strategy ~= prev and package.loaded["lib"] ~= nil then
    vim.notify(
      ('lib.config: strategy changed to %q after require("lib") already ran; '
        .. "this has no effect. Call lib.config.setup() before the first "
        .. 'require("lib").'):format(M.options.strategy),
      vim.log.levels.WARN
    )
  end
end

---@return Lib.Config.Options
function M.get()
  return M.options
end

---Resolve the module path for the configured aggregator strategy.
---@return string
function M.strategy_module()
  return STRATEGY_MODULES[M.options.strategy] or STRATEGY_MODULES.metatable
end

return M
