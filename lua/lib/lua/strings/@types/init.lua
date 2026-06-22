---@meta
---@module 'lib.lua.strings'
--- Public string helper facade.
--- This file exists purely for LuaLS type propagation.
--- It describes the full API returned by `require("lib.lua.strings")`.

-- =========================================================
-- Root Namespace
-- =========================================================
---@class Lib.Strings
---@field core Lib.Strings.Core
---@field links Lib.Strings.Links
---@field patterns Lib.Strings.Patterns
---@field convert Lib.Strings.Convert

-- ALL String Functions
---@class Lib.Strings.ALL
-- =========================================================
-- lib.lua.strings.core
-- =========================================================
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
-- =========================================================
-- lib.lua.strings.links
-- =========================================================
---@field uri_decode fun(s: string): string
---@field normalize_anchor fun(s: string): string
---@field has_scheme fun(s: string): boolean
---@field is_web_url fun(s: string): boolean
---@field url_under_cursor fun(line: string, col: integer): string|nil
-- =========================================================
-- lib.lua.strings.patterns
-- =========================================================
---@field escape_lua_magic fun(s: string): string
---@field find_plain fun(s: string, needle: string): integer|nil, integer|nil
---@field replace_plain fun(s: string, from: string, to: string): string
---@field surround fun(s: string, left: string, right: string): string
-- =========================================================
-- lib.lua.strings.transform
-- =========================================================
---@field remove_prefix fun(s: string, list?: string[]): string
---@field trim fun(s: any): string
---@field slugify fun(s: string): string
---@field kebab_case fun(s: string): string
---@field snake_case fun(s: string): string
---@field camel_case fun(s: string): string
---@field capitalize fun(s: string): string
---@field uncapitalize fun(s: string): string
---@field normalize_ws fun(s: string): string|nil
---@field pad_start fun(s: string, width: integer): string
---@field pad_end fun(s: string, width: integer): string
---@field pad_center fun(s: string, width: integer): string
---@field indent fun(s: string, n: integer): string
---@field dedent fun(s: string): string
-- =========================================================
-- lib.lua.strings.convert
-- =========================================================
---@field hex_to_string fun(hex: string): string

---@type Lib.Strings
local strings

return strings


---@class LibStringsCore

---@class LibStringsPatterns
