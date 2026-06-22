---@module 'lib.lua.strings.@types.links'
-- =========================================================
-- lib.lua.strings.links
-- =========================================================

---@class Lib.Strings.Links
---@field uri_decode fun(s: string): string
---@field normalize_anchor fun(s: string): string
---@field has_scheme fun(s: string): boolean
---@field is_web_url fun(s: string): boolean
---@field url_under_cursor fun(line: string, col: integer): string|nil

return {}
