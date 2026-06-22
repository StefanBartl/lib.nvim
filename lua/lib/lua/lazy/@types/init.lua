---@meta
---@module 'lib.lua.lazy.@types'

---@class Lib.Lazy
---@field _loader fun(): table
---@field _value table|nil
---@field get? fun(): table Returns the loaded module. Loads it exactly once on first invocation.

return {}
