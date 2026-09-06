---@meta
---@module 'lib.nvim.normalize.types'

---@class Lib.Normalize.StringListOpts
--- Configuration options for string list normalization.
---@field sep string|nil Separator pattern (default: "[%s,]+")
---@field trim boolean|nil Whether to trim whitespace from tokens
---@field dedup boolean|nil Whether to deduplicate entries

---@class Lib.Normalize : Lib.Normalize.Utils, Lib.Normalize.Validators
--- The flattened table returned by `require("lib.nvim.normalize")`: every
--- field of Utils and Validators merged onto one table (see those two
--- classes for the actual per-function docs). All to_*/is_*/*_valid
--- functions are side-effect free and return nil/false on invalid input.

return {}
