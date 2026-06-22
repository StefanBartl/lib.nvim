
---@meta
---@module 'lib.nvim.ui.hover_select.@types.config'

---@class Lib.UI.HoverSelect.Config
---@description
--- Typdefinitionen für die statische Standardkonfiguration von lib.nvim.ui.hover_select.
--- Enthält Default-Werte für Buffer-, Window- und Layout-Einstellungen,
--- die beim Öffnen eines Hover-Select-Fensters verwendet werden.

---@class Lib.UI.HoverSelect.Config.BufferOptions
---@description
--- Default-Buffer-Optionen für Hover-Select.
--- Diese Optionen werden auf den temporären, ungelisteten Buffer angewendet.
---@field buftype string
---@field bufhidden string
---@field swapfile boolean
---@field modifiable boolean
---@field filetype string

---@class Lib.UI.HoverSelect.Config.WindowOptions
---@description
--- Default-Window-Optionen für das Hover-Select-Floating-Window.
---@field cursorline boolean
---@field number boolean
---@field relativenumber boolean
---@field wrap boolean
---@field spell boolean
---@field foldenable boolean
---@field signcolumn string

---@class Lib.UI.HoverSelect.Config.WindowConfig
---@description
--- Default-Fensterkonfiguration für das Floating-Window.
--- Entspricht weitgehend den Parametern von nvim_open_win.
---@field relative string
---@field row integer
---@field col integer
---@field style string
---@field border string
---@field focusable boolean
---@field zindex integer

---@class Lib.UI.HoverSelect.Config.Dimensions
---@description
--- Einschränkungen für die Fenstergröße.
--- Werden u. a. bei Auto-Width- und Auto-Height-Berechnungen genutzt.
---@field min_width integer
---@field max_width integer
---@field min_height integer
---@field max_height integer
---@field padding integer

---@class Lib.UI.HoverSelect.Config.Module
---@description
--- Öffentliche Konfigurationsschnittstelle des Moduls.
---@field default_buf_options Lib.UI.HoverSelect.Config.BufferOptions
---@field default_win_options Lib.UI.HoverSelect.Config.WindowOptions
---@field default_win_config Lib.UI.HoverSelect.Config.WindowConfig
---@field dimensions Lib.UI.HoverSelect.Config.Dimensions

return {}
