---@meta
---@module 'lib.nvim.normalize.@types.utils'
-- =========================================================
-- Utility Functions
-- =========================================================

---@class Lib.Normalize.Utils
---@field trim fun(s: any): string # Trim leading and trailing ASCII whitespace from string. # Returns empty string if input is not a string.
---
---@field clamp fun(n: number, min?: number, max?: number): number # Clamp number into [min, max] range (inclusive). Nil min/max values are ignored.
---
---@field coalesce fun(...: any): any # Return the first non-nil argument. Returns nil if all arguments are nil.
---
---@field normalize_path fun(p: any): string # Normalize filesystem path using Neovim facilities if available.
--- Uses vim.fs.normalize when present, otherwise provides fallback that:
---   • Collapses consecutive slashes
---   • Strips trailing slash (except for root)
--- Returns empty string if input is invalid.
---
---@field path_kind fun(p: string): string # Determine path type using libuv if available. Returns: "file", "directory", or "" (does not exist/unavailable).
---
---@field dedup_strings fun(list: Lib.Normalize.StringList): Lib.Normalize.StringList # Deduplicate string list while preserving first occurrence order. Non-string entries are filtered out.

return {}
