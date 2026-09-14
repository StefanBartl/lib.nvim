---@meta
---@module 'lib.lua.range.@types'

---@class Lib.Range.ParseOpts
---@field min? integer Reject the spec if any parsed number is below this.
---@field max? integer Reject the spec if any parsed number is above this.

---@class Lib.Range
---@field parse fun(spec: string, opts?: Lib.Range.ParseOpts): integer[]|nil, string|nil Parse `"1-3,5,7"`-style spec into a sorted, deduplicated integer list.

return {}
