---@meta
---@module 'lib.nvim.selection.@types'

---@class Lib.Selection
---@field lines fun(): integer, integer # 0-based inclusive (srow, erow) row range of the active Visual selection
---@field reselect_lines fun(srow: integer, erow: integer): nil # Restore a linewise (`V`) selection over `[srow, erow]` (0-based inclusive)
---@field keep_lines fun(fn: fun(srow: integer, erow: integer): any): any # Run `fn(srow, erow)` against the current selection's rows, then reselect them linewise
---@field chars fun(): integer|nil, integer|nil, integer|nil # 0-based (row, scol, ecol) of a same-line charwise selection, or nil if not applicable
---@field reselect_chars fun(row: integer, scol: integer, ecol: integer): nil # Restore a charwise (`v`) selection spanning byte columns `[scol, ecol]` (0-based inclusive) on `row`
---@field keep_chars fun(fn: fun(row: integer, scol: integer, ecol: integer): any): any, boolean # Run `fn(row, scol, ecol)` against the current same-line charwise selection and reselect it; `applicable` is false (and `fn` is not called) when the selection isn't same-line charwise
