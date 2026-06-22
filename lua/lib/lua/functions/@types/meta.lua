---@meta
---@module 'lib.lua.functions.@types.meta'

---@class Lib.Functions.Meta
---@field noop fun(): nil # No-operation function. Explicitly does nothing and returns nil.
---@field identity fun(v: any): any # Identity function. Returns the value it was given unchanged. Commonly used in functional pipelines as a default mapper or when a transformation hook is optional.
---@field always_true fun(): boolean # Constant-true predicate. Always returns true regardless of input. Useful as a default filter or guard function.
---@field always_false fun(): boolean # Constant-false predicate. Always returns false regardless of input. Useful as a disabling predicate or sentinel.
---@field const fun(value: any): fun(): any # Constant value generator. Returns a function that always yields the provided value. Useful for lazy defaults, dependency injection, or testing.
---@field raise fun(err: any): nil # Error passthrough helper. Always throws an error. LuaLS has no `never` type, so `nil` is used as a pragmatic substitute.

return {}

