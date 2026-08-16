---@meta
---@module 'lib.lua.context_manager.@types'

---@class Lib.ContextManager
---@field with fun(acquire: fun(): any, string|nil, release: fun(resource: any), body: fun(resource: any): ...): boolean, ... Run `body(resource)` with guaranteed cleanup.

return {}
