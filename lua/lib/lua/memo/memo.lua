---@module 'lib.lua.memo.memo'
--- Memoization helpers backed by LRU cache from lib.lua.memo.lru.

local LRU = require("lib.lua.memo.lru")

local M = {}

--- Memoize a pure function by its argument tuple.
--- Note: keys are created from tostring(...) which is fine for primitives/strings.
--- For complex keys, pass a keyer that returns a unique string.
---@param fn fun(...): any # Function to memoize
---@param cap integer|nil # Cache capacity (default: 128)
---@param keyer fun(...): string|nil # Optional custom key generator
---@return fun(...): any # Memoized function
function M.memoize(fn, cap, keyer)
  -- Validate and sanitize capacity
  local capacity = cap
  if capacity == nil then
    capacity = 128
  end
  if type(capacity) ~= "number" then
    error(("memoize: cap must be number or nil, got %s"):format(type(capacity)), 2)
  end

  local lru = LRU.new(capacity)

  return function(...)
    local key = keyer and keyer(...) or table.concat({ ... }, "\31") -- unit separator
    local hit = lru:get(key)
    if hit ~= nil then
      return hit
    end
    local val = fn(...)
    if val == nil then
      -- Don't cache nil values
      return nil
    end
    lru:put(key, val)
    return val
  end
end

--- Generate a stable cache key from arguments
---@param ... any
---@return string
local function default_keyer(...)
  local args = { ... }
  local parts = {}

  for i = 1, #args do
    local arg = args[i]
    local t = type(arg)

    if t == "table" then
      -- Deep serialize tables (simple implementation)
      parts[i] = vim.inspect(arg)
    elseif t == "function" then
      -- Functions: use tostring (address)
      parts[i] = tostring(arg)
    elseif t == "nil" then
      parts[i] = "nil"
    else
      -- Primitives: tostring
      parts[i] = tostring(arg)
    end
  end

  return table.concat(parts, "\31") -- unit separator
end

-- ---@field memoize2 fun(fn: fun(...): any, cap: integer|nil, keyer: fun(...): string|nil): fun(...): any # Memoize a pure function by its argument tuple. Keys are created from tostring(...) which is fine for primitives/strings. This fixes the string-concat bug with complex arguments For complex keys, pass a keyer that returns a unique string.

--- Memoize a pure function by its argument tuple.
--- Note: keys are created from tostring(...) which is fine for primitives/strings.
---   - This fixes the string-concat bug with complex arguments
-- For complex keys, pass a keyer that returns a unique string.
---@param fn fun(...): any # Function to memoize
---@param cap integer|nil # Cache capacity (default: 128)
---@param keyer fun(...): string|nil # Optional custom key generator
---@return fun(...): any # Memoized function
function M.memoize2(fn, cap, keyer)
  -- Validate and sanitize capacity
  local capacity = cap
  if capacity == nil then
    capacity = 128
  end
  if type(capacity) ~= "number" then
    error(("memoize: cap must be number or nil, got %s"):format(type(capacity)), 2)
  end

  local lru = LRU.new(capacity)
  local key_fn = keyer or default_keyer

  return function(...)
    local key = key_fn(...)
    local hit = lru:get(key)
    if hit ~= nil then
      return hit
    end
    local val = fn(...)
    if val == nil then
      -- Don't cache nil values
      return nil
    end
    lru:put(key, val)
    return val
  end
end

return M
