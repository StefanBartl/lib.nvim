---@meta
---@module 'lib.lua.patterns.middleware.@types'

---@class Lib.Patterns.Middleware
---@field stages (fun(ctx: table, next: fun(): ...): ...)[]
---@field use fun(self: Lib.Patterns.Middleware, stage: fun(ctx: table, next: fun(): ...): ...): Lib.Patterns.Middleware
---@field run fun(self: Lib.Patterns.Middleware, ctx: table, final: (fun(ctx: table): ...)|nil): ...
