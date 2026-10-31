---@meta
---@module 'lib.lua.patterns.reducer.@types'

---@class Lib.Patterns.ReducerStore
---@field reduce fun(state: any, action: table): any
---@field current any
---@field listeners function[]
---@field state fun(self: Lib.Patterns.ReducerStore): any
---@field dispatch fun(self: Lib.Patterns.ReducerStore, action: table): boolean, any
---@field subscribe fun(self: Lib.Patterns.ReducerStore, fn: fun(new: any, old: any, action: table)): fun()
