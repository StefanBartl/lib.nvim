---@meta
---@module 'lib.lua.patterns.repository.@types'

---@class Lib.Patterns.Store
---@field get fun(id: any): any
---@field put fun(id: any, value: any)
---@field delete fun(id: any)
---@field all fun(): { id: any, value: any }[]

---@class Lib.Patterns.Repository
---@field store Lib.Patterns.Store
---@field get fun(self: Lib.Patterns.Repository, id: any): any
---@field save fun(self: Lib.Patterns.Repository, id: any, value: any)
---@field remove fun(self: Lib.Patterns.Repository, id: any)
---@field all fun(self: Lib.Patterns.Repository): { id: any, value: any }[]
---@field find fun(self: Lib.Patterns.Repository, predicate: fun(value: any, id: any): boolean): { id: any, value: any }|nil
---@field filter fun(self: Lib.Patterns.Repository, predicate: fun(value: any, id: any): boolean): { id: any, value: any }[]
---@field count fun(self: Lib.Patterns.Repository): integer
