---@module 'lib.lua.functions.meta'
-- =========================================================
-- Small functional and meta helpers.
--
-- This module contains intentionally tiny, allocation-free
-- utility functions that are commonly useful as defaults,
-- placeholders, or adapters in APIs and control-flow.
--
-- All functions are side-effect free unless explicitly noted.
-- =========================================================

local M = {}

--- No-operation function.
---
--- Explicitly does nothing and returns nil.
--- Useful as:
--- - default callback
--- - intentional empty branch target
--- - placeholder to avoid empty-block diagnostics
--- - semantic marker for "intentionally ignored"
---@return nil
function M.noop()
  ---@diagnostic disable-next-line: redundant-return
  return
end

--- Identity function.
---
--- Returns the value it was given unchanged.
--- Commonly used in functional pipelines as a default mapper
--- or when a transformation hook is optional.
---@generic T
---@param v T
---@return T
function M.identity(v)
  return v
end

--- Constant-true predicate.
---
--- Always returns true regardless of input.
--- Useful as a default filter or guard function.
---@return boolean
function M.always_true()
  return true
end

--- Constant-false predicate.
---
--- Always returns false regardless of input.
--- Useful as a disabling predicate or sentinel.
---@return boolean
function M.always_false()
  return false
end

--- Constant value generator.
---
--- Returns a function that always yields the provided value.
--- Useful for lazy defaults, dependency injection, or testing.
---@generic T
---@param value T
---@return fun(): T
function M.const(value)
  return function()
    return value
  end
end

--- Error passthrough helper.
---
--- Always throws an error.
--- LuaLS has no `never` type, so `nil` is used as a pragmatic substitute.
---@param err any
---@return nil
function M.raise(err)
  error(err, 0)
end

---@type Lib.Functions.Meta
return M

