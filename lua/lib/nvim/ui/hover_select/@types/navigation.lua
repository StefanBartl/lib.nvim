---@meta
---@module 'lib.nvim.ui.hover_select.@types.navigation'

---@class Lib.UI.HoverSelect.Navigation
---@description
--- Navigation- und Keymap-Setup für das Hover-Select-Plugin.
--- Legt Buffer-local Keymaps fest, blockiert horizontale Bewegung
--- und bindet Aktionen für Auswahl, Toggle und Schließen.
---
---@field setup fun(bufnr: integer, on_select: fun(), on_toggle: fun()|nil) # Setzt Navigation-Keymaps für einen Hover-Select-Buffer.
--- `on_select` wird bei Enter oder Mausklick ausgeführt.
--- `on_toggle` ist optional und aktiviert Multi-Select mit Tab/Shift-Tab.
---
---@field _block_horizontal_movement fun(bufnr: integer) # Blockiert horizontale Cursorbewegung (h/l, <Left>/<Right>, 0, $, w, b, e etc.) in allen Modi, um das Hover-Select auf Zeilen-Navigation zu beschränken.

return {}

