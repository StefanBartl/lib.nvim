---@module 'lib.lua.memo.memo'
--- Memoization helpers backed by LRU cache from lib.lua.memo.lru.

local LRU = require("lib.lua.memo.lru")

local M = {}

--- Type tags for `key_of`, so that f(1) and f("1") do not share a cache entry.
local TAG = {
  string = "s",
  number = "n",
  boolean = "b",
  ["nil"] = "z",
  table = "t",
  ["function"] = "f",
  userdata = "u",
  thread = "c",
}

--- Build a cache key from an argument tuple.
---
--- This used to be `table.concat({ ... }, "\31")`, which throws on anything
--- `concat` will not take -- a boolean, a table, a TSNode. Callers that passed
--- one got `invalid value (userdata) at index 1 in table for 'concat'` from
--- inside the memo wrapper, nowhere near their own call site.
---
--- Two further things the old key got wrong, fixed here because a key that
--- silently collides is worse than one that throws:
---   - `f(1)` and `f("1")` produced the same key. Each part is tagged now.
---   - `select("#")`, not `#args`: `{ ... }` with a nil in it has no reliable
---     length, so `f(nil, 2)` and `f(2)` could land on the same key.
---
--- Reference types (table, function, userdata, thread) are keyed by address.
--- That is correct only while the object outlives the cache entry -- addresses
--- get recycled, so a short-lived object (a TSNode from a tree that is
--- reparsed, say) can hand a later object the earlier one's cached value. For
--- those, pass a `keyer` that derives something stable from the value, or do
--- not memoize at all.
---@param ... any
---@return string
local function key_of(...)
  local n = select("#", ...)
  local parts = {}

  for i = 1, n do
    local arg = select(i, ...)
    parts[i] = TAG[type(arg)] .. ":" .. tostring(arg)
  end

  return table.concat(parts, "\31") -- unit separator
end

--- Memoize a pure function by its argument tuple.
--- Keys are built by `key_of`, which accepts any argument type -- read its note
--- before memoizing a function that takes a short-lived reference type.
--- For anything else, pass a `keyer` that returns a unique string.
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
    local key = keyer and keyer(...) or key_of(...)
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
---@internal
---@param ... any
---@return string
local function default_keyer(...)
  -- `select("#", ...)`, not `#{ ... }`: a tuple with a nil in it has no
  -- reliable length, so f(nil, 2) and f(2) could produce the same key.
  local n = select("#", ...)
  local parts = {}

  for i = 1, n do
    local arg = select(i, ...)
    local t = type(arg)

    if t == "table" then
      --- CDX: `vim.inspect` here makes `lib.lua.memo` depend on the `vim` API,
      --- CDX: which architecture.md says `lib.lua.*` must not. Only reached by
      --- CDX: `memoize2` without a custom keyer.
      parts[i] = TAG[t] .. ":" .. vim.inspect(arg)
    else
      -- Everything else by value or, for reference types, by address --
      -- see the note on `key_of` for when that is safe.
      parts[i] = TAG[t] .. ":" .. tostring(arg)
    end
  end

  return table.concat(parts, "\31") -- unit separator
end

--- Memoize a pure function by its argument tuple.
--- Like `memoize`, but the default key generator serializes table arguments
--- (via `vim.inspect`) instead of relying on `table.concat`, which drops them.
--- Pass a `keyer` to override.
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
