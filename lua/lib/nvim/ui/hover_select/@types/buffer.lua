---@meta
---@module 'lib.nvim.ui.hover_select.@types.buffer'

---@class Lib.UI.HoverSelect.Buffer
---@description
--- Öffentliche Buffer-API für lib.nvim.ui.hover_select.
--- Kapselt die Erstellung und Aktualisierung von Neovim-Buffern,
--- die als Datenquelle für das Hover-Select-Fenster dienen.
---
---@field create fun(items: string[], buf_options: table<string, any>): integer|nil # Erstellt einen neuen, ungelisteten Buffer und befüllt ihn mit den übergebenen Items.
--- Setzt temporär `modifiable=true`, schreibt die Zeilen und wendet
--- anschließend die konfigurierten Buffer-Optionen an.
--- Gibt die Buffer-Nummer zurück oder nil bei Fehlern.
---
---@field update_content fun(bufnr: integer, items: string[]): boolean # Aktualisiert den Inhalt eines bestehenden Buffers.
--- Prüft zuerst die Gültigkeit des Buffers, setzt `modifiable`
--- temporär auf true, ersetzt alle Zeilen und stellt den vorherigen
--- Zustand wieder her.
--- Gibt true zurück, wenn die Aktualisierung erfolgreich war.

return {}
