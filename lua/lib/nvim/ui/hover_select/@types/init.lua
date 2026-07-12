---@meta
---@module 'lib.nvim.ui.hover_select.@types'

-- === INIT ===

---@class Lib.UI.HoverSelect
---@description
--- Public API of the hover-select UI module. Since the chooser was absorbed into
--- lib.nvim.ui.kit, this is a thin shim over lib.nvim.ui.kit.chooser; the surface
--- below is unchanged for backward compatibility.
---
---@field open fun(opts: Lib.HoverSelect.Options): integer|nil, integer|nil
--- Open a hover-select window. Returns buffer and window id, or nil on failure.
---
---@field close fun()
--- Close the active hover-select window.
---
---@field is_open fun(): boolean
--- Whether a hover-select window is currently open and valid.

---@class Lib.HoverSelect.Options
---@field items string[] List of items to display (one per line)
---@field on_select fun(selected: string|string[], index: integer|integer[]): nil Callback when item(s) selected
---@field multi_select? boolean Enable multi-selection with Tab/Shift-Tab (default: false)
---@field buf_options? table<string, any> Additional buffer options to merge
---@field win_options? table<string, any> Additional window options to merge
---@field title? string Optional window title
---@field relative? string Window positioning ('cursor', 'win', 'editor')
---@field width? integer Window width (default: auto-calculated)
---@field height? integer Window height (default: auto-calculated)
---@field use_tab_navigation? boolean
---@field auto_width? boolean

---@class Lib.HoverSelect.State
---@field bufnr integer|nil        # Active buffer number
---@field winid integer|nil        # Active window id
---@field items any[]              # Items shown in the selection window
---@field on_select fun(...)|nil   # Selection callback
---@field multi_select boolean     # Whether multi-selection is enabled
---@field selections table<integer, boolean> # Selected line indices
---@field ns_id integer            # Highlight namespace id

return {}
