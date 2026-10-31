---@meta
---@module 'lib.lua.patterns.command.@types'

---@class Lib.Patterns.Command
---@field name string|nil
---@field run fun(...): any            # Does the work; returns the state `undo` needs.
---@field undo (fun(state: any, ...))|nil

---@class Lib.Patterns.CommandHistory
---@field limit integer
---@field undo_stack table[]
---@field redo_stack table[]
---@field run fun(self: Lib.Patterns.CommandHistory, cmd: Lib.Patterns.Command, ...: any): any
---@field can_undo fun(self: Lib.Patterns.CommandHistory): boolean
---@field can_redo fun(self: Lib.Patterns.CommandHistory): boolean
---@field undo fun(self: Lib.Patterns.CommandHistory): string|nil
---@field redo fun(self: Lib.Patterns.CommandHistory): string|nil
---@field names fun(self: Lib.Patterns.CommandHistory): string[]
---@field clear fun(self: Lib.Patterns.CommandHistory)
