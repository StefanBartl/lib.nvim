---@meta
---@module 'lib.lua.tables.@types.paths'
-- =========================================================
-- Path Flattening
-- =========================================================

---@class Lib.Tables.Paths.FlattenOpts
---@field sep? string        -- path separator, default "."
---@field max_depth? integer -- recursion guard, default 64

---@class Lib.Tables.Paths
---@field flatten fun(value: any, opts?: Lib.Tables.Paths.FlattenOpts): ({path: string, value: any}[]|nil), (string|nil) # Flatten a nested value into {path, value}[] leaves, sorted-key order for objects, natural order for arrays. Returns nil + error on max-depth overflow.

return {}
