---@meta
---@module 'lib.nvim.diff.word_ranges.@types'

---The changed spans of both sides: 0-based `[from, to)` byte ranges, in file order.
---@class Lib.Diff.WordRanges.Result
---@field a integer[][]  ranges in the old text
---@field b integer[][]  ranges in the new text

---@alias Lib.Diff.WordRanges fun(a: string, b: string, algorithm?: "myers"|"minimal"|"patience"|"histogram"): Lib.Diff.WordRanges.Result|nil

return {}
