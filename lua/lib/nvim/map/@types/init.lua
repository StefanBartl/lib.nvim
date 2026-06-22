---@meta
---@module 'lib.nvim.map.@types'

---@class Lib.Map.ErrorFlags
---@field modes boolean
---@field lhs boolean
---@field rhs boolean
---@field buffer boolean

---@class Lib.Map.Opts
---@field noremap? boolean
---@field silent? boolean
---@field buffer? integer|boolean
---@field desc? string

---@class Lib.Map
---@field _call fun(modes: string|string[], lhs: string, rhs: string|function, opts: Lib.Map.Opts|nil, desc: string?): nil

return {}
