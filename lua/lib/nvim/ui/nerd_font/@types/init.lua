---@meta
---@module 'lib.nvim.ui.nerd_font.@types'

---@class Lib.UI.NerdFont
---@field available fun(): boolean
---@field glyph fun(hex: string, fallback: string): string
---@field chars fun(rich: string[], fallback: string[]): string[]
---@field sep fun(hex: string, fallback: string, pad: string|nil): string

return {}
