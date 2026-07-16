---@module 'lib.lua.error'
--- Structured-error + safe-call-with-traceback convention, pure Lua.
---
--- `M.new` builds a plain table describing an error (`kind`, `message`,
--- optional `data`) tagged with a `__lib_error` marker field so `M.is` can
--- recognize it. `M.safe_call` wraps a function call in `xpcall` with
--- `debug.traceback` as the message handler, returning `true, ...` on
--- success (all of `fn`'s return values preserved) or
--- `false, <structured error>` on failure.

---@type LibError
local M = {}

---Build a structured error table.
---@nodiscard
---@param kind string
---@param message string
---@param data any? Optional extra context
---@return LibErrorValue err `{ kind, message, data, __lib_error = true }`
function M.new(kind, message, data)
  assert(type(kind) == "string", "kind must be a string")
  assert(type(message) == "string", "message must be a string")

  return {
    kind = kind,
    message = message,
    data = data,
    __lib_error = true,
  }
end

---True iff `value` is a table produced by `M.new`.
---@nodiscard
---@param value any
---@return boolean
function M.is(value)
  return type(value) == "table" and value.__lib_error == true
end

-- LuaJIT (Lua 5.1) has neither `table.pack` nor `table.unpack`: it provides
-- the global `unpack` and no `pack` at all. Neovim runs on LuaJIT, so both
-- need a 5.1 fallback.
local unpack_fn = table.unpack or unpack

--- Mirrors Lua 5.2's `table.pack` (returns `{ ..., n = <count> }`), which
--- LuaJIT lacks. `n` is what makes embedded `nil`s survive the round-trip.
---@param ... any
---@return table
local pack_fn = table.pack
  or function(...)
    return { n = select("#", ...), ... }
  end

---Call `fn(...)` guarded by `xpcall`, capturing a full traceback on failure.
---
---Correctly forwards multiple return values (and embedded `nil`s), so
---callers can do: `local ok, a, b, c = M.safe_call(fn, ...)`.
---@param fn function
---@param ... any Arguments forwarded to `fn`
---@return boolean ok
---@return any ... On success: all return values of `fn`. On failure: a single `LibErrorValue` (`kind = "runtime_error"`, `message` = traceback string).
function M.safe_call(fn, ...)
  local args = pack_fn(...)

  local outcome = pack_fn(xpcall(function()
    return fn(unpack_fn(args, 1, args.n))
  end, debug.traceback))

  local ok = outcome[1]
  if not ok then
    local traceback = outcome[2]
    return false, M.new("runtime_error", traceback)
  end

  return true, unpack_fn(outcome, 2, outcome.n)
end

return M
