---@meta
---@module 'lib.lua.patterns.builder.@types'

---@class Lib.Patterns.Builder.Field
---@field default any
---@field required boolean|nil
---@field validate (fun(v: any): boolean)|nil

---@class Lib.Patterns.Builder
---@field _schema table<string, Lib.Patterns.Builder.Field>
---@field _values table<string, any>
---@field set fun(self: Lib.Patterns.Builder, name: string, value: any): Lib.Patterns.Builder
---@field get fun(self: Lib.Patterns.Builder, name: string): any
---@field build fun(self: Lib.Patterns.Builder): table|nil, string|nil
