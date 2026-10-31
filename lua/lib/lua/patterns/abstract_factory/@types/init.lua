---@meta
---@module 'lib.lua.patterns.abstract_factory.@types'

---@class Lib.Patterns.AbstractFactory
---@field families table<string, table<string, function>>
---@field names fun(self: Lib.Patterns.AbstractFactory): string[]
---@field family fun(self: Lib.Patterns.AbstractFactory, name: string): table<string, function>
---@field create fun(self: Lib.Patterns.AbstractFactory, name: string, product: string, ...: any): any
