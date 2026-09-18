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

---@internal
---An unknown key, with the nearest known one as a hint when there is a
---plausible one.
---@param key any
---@return string
local function describe_unknown(key)
  local levenshtein = require("lib.lua.strings.distance").levenshtein
  local name = tostring(key)
  local best, best_distance = nil, nil
  for known in pairs(defaults) do
    local d = levenshtein(name, known)
    if d <= 3 and (best_distance == nil or d < best_distance) then
      best, best_distance = known, d
    end
  end
  return best and ("%s (did you mean %s?)"):format(name, best) or name
end

---Merge user options.
---
---Unknown keys are reported before anything is merged and are not stored:
---a typo such as `startegy = "eager"` would otherwise land in `M.options`
---as a dead field while the default stays in force, and nothing would ever
---say so.
---@param opts Lib.Config.Options|nil
function M.setup(opts)
  opts = opts or {}
  local prev = M.options.strategy

  local known, unknown = {}, {}
  for key, value in pairs(opts) do
    if defaults[key] ~= nil then
      known[key] = value
    else
      unknown[#unknown + 1] = describe_unknown(key)
    end
  end
  if #unknown > 0 then
    table.sort(unknown)
    vim.notify(
      ("lib.config: unknown option(s) ignored: %s"):format(table.concat(unknown, ", ")),
      vim.log.levels.WARN
    )
  end

  M.options = vim.tbl_extend("force", M.options, known)

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
      (
        'lib.config: strategy changed to %q after require("lib") already ran; '
        .. "this has no effect. Call lib.config.setup() before the first "
        .. 'require("lib").'
      ):format(M.options.strategy),
      vim.log.levels.WARN
    )
  end
end

---Returns the current (merged) configuration.
---@return Lib.Config.Options
function M.get()
  return M.options
end

---Resolve the module path for the configured aggregator strategy.
---@return string
function M.strategy_module()
  return STRATEGY_MODULES[M.options.strategy] or STRATEGY_MODULES.metatable
end

---@type Lib.Config
return M
