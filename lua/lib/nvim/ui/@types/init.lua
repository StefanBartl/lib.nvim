---@meta
---@module 'lib.nvim.ui.@types'

--- CDX: phantom aggregate-module class -- documents require("lib.nvim.ui")
--- as if it returns one table, but ui/ has no init.lua; hl/, kit/, list/,
--- nerd_font/, statusline/ are separate leaf modules required directly by
--- their own paths. Also incomplete even as a phantom: missing `statusline`
--- and `nerd_font` fields. Same recurring shape flagged in lib/@types/init.lua
--- (Sub 4) and buf_win_tab/buffer @types (Sub 5) -- pending an external-
--- consumer check before deciding whether to delete or keep.
---@class Lib.UI
---@field hl Lib.UI.HL
---@field kit Lib.UI.Kit
---@field list Lib.UI.List

return {}
