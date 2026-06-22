---@module 'lib.lua.memo'
--- Aggregated export for cache helpers with enhanced API.

local M = {}

--- Lazy require to avoid overhead on cold load.
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
---@param func fun(...): any # Function to memoize
---@param opts table|integer|nil # Options table or capacity number
---@return fun(...): any # Memoized function
function M.fn(func, opts)
  -- Handle legacy numeric capacity argument
  if type(opts) == "number" then
    return M.memo.memoize(func, opts, nil)
  end

  -- Handle options table
  opts = opts or {}
  local size = opts.size or 128
  local keyer = opts.keyer

  -- Validate size
  if type(size) ~= "number" then
    error(("memo.fn: size must be number, got %s"):format(type(size)), 2)
  end

  return M.memo.memoize(func, size, keyer)
end

---@type Lib.Memo
return M
