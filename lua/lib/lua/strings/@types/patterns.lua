---@module 'lib.lua.strings.@types.patterns'
-- =========================================================
-- lib.lua.strings.patterns
-- =========================================================

---@class Lib.Strings.Patterns
---@field escape_lua_magic fun(s: string): string
---@field find_plain fun(s: string, needle: string): integer|nil, integer|nil
---@field replace_plain fun(s: string, from: string, to: string): string
---@field surround fun(s: string, left: string, right: string): string

return {}
