---@meta
---@module 'lib.nvim.normalize.@types.aliases'

---@alias Lib.Normalize.FnApplier fun(state:table, key:string, value:any):boolean
--- Function signature for applier functions used in schema validation.
--- Takes a state table, field key, and value to apply.
--- Returns true if the value was successfully applied and written to state[key].

---@alias Lib.Normalize.StringList string[]
--- Represents a list of strings, commonly used for enum values, file lists, etc.

return {}
