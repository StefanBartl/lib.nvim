---@meta
---@module 'lib.lua.patterns.saga.@types'

---@class Lib.Patterns.SagaStep
---@field name string|nil
---@field run fun(ctx: table)
---@field compensate (fun(ctx: table))|nil
