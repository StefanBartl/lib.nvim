---@meta
---@module 'lib.nvim.health.@types'

---@class Lib.Nvim.Health
---@field version_ok fun(min: integer[]): boolean
---@field check_require fun(mod: string, label: string, level: "error"|"warn"|"info", advice?: string[]): nil

return {}
