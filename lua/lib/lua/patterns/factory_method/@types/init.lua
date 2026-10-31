---@meta
---@module 'lib.lua.patterns.factory_method.@types'

---@class Lib.Patterns.FactoryMethod
---@field ctors table<string, function>
---@field order string[]
---@field default function|nil
---@field register fun(self: Lib.Patterns.FactoryMethod, kind: string, ctor: function): Lib.Patterns.FactoryMethod
---@field create fun(self: Lib.Patterns.FactoryMethod, kind: string, ...: any): any
---@field kinds fun(self: Lib.Patterns.FactoryMethod): string[]
