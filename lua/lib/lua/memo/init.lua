---@module 'lib.lua.memo'
--- Aggregated export for cache helpers with enhanced API.

local M = {}

--- Lazy require to avoid overhead on cold load.
---@internal
---@generic T
---@param mod string
---@return T
local function lr(mod)
  return (require("lib.lua.memo." .. mod))
end

-- Existing submodules
M.lru = lr("lru")
M.memo = lr("memo")

--- Convenience function: memoize with default settings.
--- Delegates to memo.memoize but provides shorter syntax.
---
--- Reads `size` and `keyer`. Anything else in `opts` is rejected rather than
--- ignored -- `weak` was accepted in silence for as long as this function
--- existed, and ten call sites across the fleet passed it believing they had a
--- weakly-keyed cache. They never did, and could not have: `memoize` keys on
--- the *string* a keyer returns, and a weak table does not collect string
--- keys. The option was incoherent with the design rather than merely
--- unimplemented, so it is gone rather than deferred.
---@param func fun(...): any # Function to memoize
---@param opts Lib.Memo.MemoOpts|integer|nil # Options table or capacity number
---@return fun(...): any # Memoized function
function M.fn(func, opts)
  -- Handle legacy numeric capacity argument
  if type(opts) == "number" then
    return M.memo.memoize(func, opts, nil)
  end

  -- Handle options table
  opts = opts or {}
  ---@cast opts Lib.Memo.MemoOpts
  local size = opts.size or 128
  local keyer = opts.keyer

  -- Validate size
  if type(size) ~= "number" then
    error(("memo.fn: size must be number, got %s"):format(type(size)), 2)
  end

  for k in pairs(opts) do
    if k ~= "size" and k ~= "keyer" then
      error(("memo.fn: unknown option %q (reads `size` and `keyer`)"):format(tostring(k)), 2)
    end
  end

  return M.memo.memoize(func, size, keyer)
end

---@type Lib.Memo
return M
