---@meta
---@module 'lib.lua.numeral.@types'

---@class LibNumeralRoman
---@field to_roman fun(n: integer): string|nil, string|nil # Integer (1-3999) -> uppercase Roman numeral, or nil + err.
---@field to_int fun(s: string): integer|nil, string|nil # Roman numeral (case-insensitive) -> integer, or nil + err. Rejects non-canonical forms.

---@class LibNumeralAlpha
---@field to_alpha fun(n: integer): string|nil, string|nil # Integer (>= 1) -> lowercase bijective base-26 string, or nil + err.
---@field to_int fun(s: string): integer|nil # Letter string (any case) -> integer, or nil if invalid.

---@class LibNumeral
---@field roman LibNumeralRoman
---@field alpha LibNumeralAlpha
