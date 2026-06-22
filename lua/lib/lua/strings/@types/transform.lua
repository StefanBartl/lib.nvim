---@module 'lib.lua.strings.transform'
--- Type surface for string transformation helpers.

---@class Lib.Strings.Transform
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

---@type Lib.Strings.Transform
local transform

return transform

