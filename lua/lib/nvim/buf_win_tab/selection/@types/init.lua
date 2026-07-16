---@meta
---@module 'lib.nvim.buf_win_tab.selection.@types'

---A resolved visual selection.
---Rows are 1-based; columns are 1-based and inclusive on both ends
---(directly usable with `string.sub`).
---@class Lib.BufWinTab.Selection
---@field lines string[] Selected text, already sliced by column
---@field start_row integer 1-based first row
---@field start_col integer 1-based inclusive first column
---@field end_row integer 1-based last row
---@field end_col integer 1-based inclusive last column

---@class Lib.BufWinTab.SelectionModule
---@field get_visual_selection fun(): Lib.BufWinTab.Selection|nil
---@field reselect_visual fun(): boolean
