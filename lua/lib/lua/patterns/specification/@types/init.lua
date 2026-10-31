---@meta
---@module 'lib.lua.patterns.specification.@types'

---@class Lib.Patterns.Specification
---@field check fun(candidate: any): boolean
---@field is_satisfied_by fun(self: Lib.Patterns.Specification, candidate: any): boolean
---@field and_ fun(self: Lib.Patterns.Specification, other: Lib.Patterns.Specification): Lib.Patterns.Specification
---@field or_ fun(self: Lib.Patterns.Specification, other: Lib.Patterns.Specification): Lib.Patterns.Specification
---@field not_ fun(self: Lib.Patterns.Specification): Lib.Patterns.Specification
