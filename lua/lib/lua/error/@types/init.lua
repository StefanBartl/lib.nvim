---@meta
---@module 'lib.lua.error.@types'

---@class LibErrorValue
---@field kind string
---@field message string
---@field data any
---@field __lib_error true

---@class LibError
---@field new fun(kind: string, message: string, data: any?): LibErrorValue
---@field is fun(value: any): boolean
---@field safe_call fun(fn: function, ...: any): boolean, ...
