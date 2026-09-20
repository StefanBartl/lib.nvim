---@module 'lib.lua.memo.memo'
--- Memoization helpers backed by LRU cache from lib.lua.memo.lru.

local LRU = require("lib.lua.memo.lru")

local M = {}

--- Type tags for `key_of`, so that f(1) and f("1") do not share a cache entry.
---
--- Covers Lua's 8 standard types. LuaJIT adds a 9th, `cdata` (any `ffi.new`
--- value, and the `vim.uv`/`luv` handles that are common in Neovim plugins),
--- which is not in this table on purpose: every unmapped type falls through
--- to `UNKNOWN_TAG` in `key_of`/`default_keyer` below rather than indexing
--- this table and getting nil. A missing key here used to mean
--- `nil .. #s .. ":" .. s` -- the exact "throws from inside the wrapper"
--- failure this whole rewrite exists to rule out, just moved to a type this
--- table's original 8 entries didn't anticipate.
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

--- Tag for any type not in `TAG` above (LuaJIT's `cdata`, or whatever a future
--- Lua adds). All such types share this one tag, so two values of *different*
--- unmapped types are distinguished only by their `tostring` -- theoretically
--- collidable if two different exotic types ever rendered identically, but
--- that is strictly better than the throw this replaces, and today `cdata` is
--- the only type that reaches it.
local UNKNOWN_TAG = "?"

--- Build a cache key from an argument tuple.
---
--- This used to be `table.concat({ ... }, "\31")`, which throws on anything
--- `concat` will not take -- a boolean, a table, a TSNode. Callers that passed
--- one got `invalid value (userdata) at index 1 in table for 'concat'` from
--- inside the memo wrapper, nowhere near their own call site.
---
--- Further things the old key got wrong, fixed here because a key that
--- silently collides is worse than one that throws:
---   - `f(1)` and `f("1")` produced the same key. Each part is tagged now.
---   - `select("#")`, not `#args`: `{ ... }` with a nil in it has no reliable
---     length, so `f(nil, 2)` and `f(2)` could land on the same key.
---   - A tag alone does not stop a string argument from forging a tuple
---     boundary: `key_of("a\31s:b")` and `key_of("a", "b")` both used to
---     serialize to `"s:a\31s:b"`, because the "\31" and the next tag's own
---     text were just more bytes the string was free to contain. Any caller
---     whose argument content is attacker- or user-influenced (buffer text,
---     a search query, a path) could use that to make one call read back the
---     cached value of a different, unrelated call. Each part is length-
---     prefixed now -- `tag .. #s .. ":" .. s` -- so the boundary is fixed by
---     a byte count the content cannot rewrite; two encodings can only be
---     equal if every part, and therefore the arity, was the same.
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
    local s = tostring(arg)
    parts[i] = (TAG[type(arg)] or UNKNOWN_TAG) .. #s .. ":" .. s
  end

  return table.concat(parts, "\31") -- unit separator, redundant but readable
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
  --
  -- Each part is length-prefixed (`tag .. #s .. ":" .. s`), not just tagged --
  -- see the note on `key_of` for why a tag alone does not stop a string (or a
  -- table whose `vim.inspect` rendering contains one) from forging a tuple
  -- boundary and colliding with an unrelated call.
  local n = select("#", ...)
  local parts = {}

  for i = 1, n do
    local arg = select(i, ...)
    local t = type(arg)
    local s

    if t == "table" then
      --- CDX: `vim.inspect` here makes `lib.lua.memo` depend on the `vim` API,
      --- CDX: which architecture.md says `lib.lua.*` must not. Only reached by
      --- CDX: `memoize2` without a custom keyer.
      s = vim.inspect(arg)
    else
      -- Everything else by value or, for reference types, by address --
      -- see the note on `key_of` for when that is safe.
      s = tostring(arg)
    end

    parts[i] = (TAG[t] or UNKNOWN_TAG) .. #s .. ":" .. s
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
