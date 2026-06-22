---@module 'lib.lua.strings.@types.core'
-- =========================================================
-- lib.lua.strings.core
-- =========================================================

---@class Lib.Strings.Core
---@field trim fun(s: any): string
---@field starts_with fun(s: string, prefix: string): boolean
---@field ends_with fun(s: string, suffix: string): boolean
---@field contains fun(s: string, needle: string): boolean
---@field split fun(s: string, sep: string): string[]
---@field join fun(parts: string[], sep: string): string
---@field replace_all fun(s: string, from: string, to: string): string
---@field normalize_ws fun(s: string): string|nil
---@field capitalize fun(s: string): string
---@field uncapitalize fun(s: string): string
---@field slugify fun(s: string): string
---@field kebab_case fun(s: string): string
---@field snake_case fun(s: string): string
---@field camel_case fun(s: string): string
---@field pad_start fun(s: string, width: integer): string
---@field pad_end fun(s: string, width: integer): string
---@field pad_center fun(s: string, width: integer): string
---@field indent fun(s: string, n: integer): string
---@field dedent fun(s: string): string
---@field is_empty_or_space fun(s: any): boolean
---@field count_lines fun(s: string): integer # Count lines in a string

return
