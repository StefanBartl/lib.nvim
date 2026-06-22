---@meta
---@module 'lib.nvim.ui.hover_select.@types'

-- === INIT ===

---@class Lib.UI.HoverSelect
---@description
--- Öffentliche API des Hover-Select-UI-Moduls.
--- Stellt Funktionen zum Öffnen, Schließen und Abfragen eines
--- interaktiven Floating-Auswahlfensters bereit.
---
---@field open fun(opts: Lib.HoverSelect.Options): integer|nil, integer|nil
--- Öffnet ein neues Hover-Select-Fenster.
--- Erstellt Buffer und Floating-Window, initialisiert Navigation,
--- Highlighting und internen Zustand.
--- Gibt Buffer- und Window-ID zurück oder nil bei Fehlern.
---
---@field close fun()
--- Schließt das aktuell geöffnete Hover-Select-Fenster.
--- Entfernt Fenster, Buffer und Highlights und setzt den Zustand zurück.
---
---@field is_open fun(): boolean
--- Prüft, ob aktuell ein Hover-Select-Fenster geöffnet und gültig ist.
--- Gibt true zurück, wenn ein gültiges Window existiert.
---
---@field _toggle_selection fun()
--- Interne Hilfsfunktion.
--- Schaltet den Selektionsstatus der aktuellen Zeile um.
--- Wird ausschließlich im Multi-Select-Modus verwendet.
---
---@field _update_selection_highlights fun()
--- Interne Hilfsfunktion.
--- Aktualisiert alle visuellen Hervorhebungen für selektierte Zeilen
--- basierend auf dem aktuellen Selektionszustand.
---
---@field _handle_selection fun()
--- Interne Hilfsfunktion.
--- Verarbeitet die finale Auswahl (Single- oder Multi-Select),
--- ruft den konfigurierten Callback auf und schließt anschließend
--- das Hover-Select-Fenster.

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
