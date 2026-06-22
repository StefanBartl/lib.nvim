---@meta
---@module 'lib.nvim.ui.hover_select.@types.window'

---@class Lib.UI.HoverSelect.Window
---@description
--- Window-Erzeugung und -Konfiguration für lib.nvim.ui.hover_select.
--- Verantwortlich für die Größenberechnung, Fenstererstellung
--- und automatische Aufräum-Autocommands.
---
---@field create fun(bufnr: integer, win_config: table, win_options: table<string, any>, items: string[]|nil, auto_width: boolean|"wrap"|nil): integer|nil # Create a floating window for the hover select buffer. Supports optional auto-width calculation. Returns window id on success, nil on failure.
---
---@field _setup_autocommands fun(bufnr: integer, winid: integer) # Internal helper to create autocmds for cleanup. Closes window on BufLeave/BufWipeout and deletes buffer on WinClosed.

return {}

