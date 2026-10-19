---@meta
---@module 'lib.lua.config.schema.@types'

---@alias Lib.Config.Schema.Spec string|Lib.Config.Schema.SpecTable

---@class Lib.Config.Schema.SpecTable
---@field [1]     string                                    Type union, see `lib.lua.config.schema`.
---@field min?    number                                    Numbers: inclusive lower bound.
---@field max?    number                                    Numbers: inclusive upper bound.
---@field enum?   string[]                                  Strings: allowed values.
---@field fields? table<string, Lib.Config.Schema.Spec>     Tables: closed record.
---@field of?     Lib.Config.Schema.Spec                    Tables: spec for every value.

---@alias Lib.Config.Schema.Fields table<string, Lib.Config.Schema.Spec>

---@class Lib.Config.Schema
---@field describe_unknown fun(key: any, known: table<string, any>, prefix: string): string
---@field check fun(value: any, spec: Lib.Config.Schema.Spec, path: string, issues: string[]): any
---@field check_record fun(body: table, fields: Lib.Config.Schema.Fields, path: string, issues: string[]): table
---@field infer fun(defaults: table, exceptions?: table<string, Lib.Config.Schema.Spec>): Lib.Config.Schema.SpecTable

return {}
