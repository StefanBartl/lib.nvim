---@module 'lib.strategies.control'
--- Introspection hook for the `require("lib")` aggregator strategies.
---
--- WHY THIS EXISTS
--- The default "metatable" strategy resolves keys through `__index` and caches
--- them in a file-local `loaded` table. Two consequences that no outside module
--- can work around on its own:
---
---   - The aggregate is an *empty* table until a key is touched, so `pairs(lib)`
---     yields nothing. Anything that needs the full key set — telemetry deriving
---     its wrap list, a health check, a docs generator — cannot discover it.
---   - `loaded[key]` keeps handing out a previously resolved value. A consumer
---     that replaces an aggregate entry needs a way to invalidate that cache,
---     and reaching into another module's local to do it is not an option.
---
--- So each strategy registers itself here with the two operations only it can
--- provide. Nothing in lib.nvim requires this to be registered: `keys()` falls
--- back to `pairs()` on the aggregate, which is already correct for the plain
--- "eager" and "lazy" tables.

local M = {}

---@class Lib.Strategies.Registration
---@field name string
---@field table table                  # the aggregate itself
---@field keys? fun(): string[]        # every key the aggregate can resolve; `M.keys` falls back to pairs() without it
---@field reset_cache? fun(): nil      # drop memoized key -> value entries

---@type Lib.Strategies.Registration|nil
local current = nil

---Called by a strategy module at load time.
---@param reg Lib.Strategies.Registration
function M.register(reg)
  current = reg
end

---@return Lib.Strategies.Registration|nil
function M.active()
  return current
end

---Every key `require("lib")` can resolve, sorted.
---
---Falls back to `pairs()` over the aggregate for strategies that expose their
---surface as a plain table.
---@param aggregate? table  # defaults to the registered aggregate
---@return string[]
function M.keys(aggregate)
  local out = {}

  if current and current.keys then
    out = current.keys()
  else
    local t = aggregate or (current and current.table)
    if type(t) == "table" then
      for k in pairs(t) do
        if type(k) == "string" then
          out[#out + 1] = k
        end
      end
    end
  end

  table.sort(out)
  return out
end

---Drop the strategy's resolved-key cache, so the next access re-resolves.
---
---A no-op for strategies that do not memoize. Returns whether anything was
---actually cleared, which is the honest answer for a caller deciding whether
---it still has to invalidate something itself.
---@return boolean cleared
function M.reset_cache()
  if current and current.reset_cache then
    current.reset_cache()
    return true
  end
  return false
end

return M
