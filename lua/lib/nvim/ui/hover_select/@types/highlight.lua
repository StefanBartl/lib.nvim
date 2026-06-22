---@meta
---@module 'lib.nvim.ui.hover_select.@types.highlight'

---@class Lib.UI.HoverSelect.Highlight
---@description
--- Öffentliche Highlight-API für lib.nvim.ui.hover_select.
--- Verantwortlich für Cursorline-Hervorhebung, Multi-Select-Markierungen
--- und das Verwalten der zugehörigen Highlight-Gruppen.
---
---@field setup fun(winid: integer) # Initialisiert Highlighting für ein Hover-Select-Fenster. Aktiviert cursorline und verknüpft sie mit einer eigenen Highlight-Gruppe.
---
---@field define_default_highlights fun() # Definiert Standard-Highlight-Gruppen für Hover-Select, falls diese noch nicht existieren. Nutzt vorhandene Gruppen wie PmenuSel oder Visual als Fallback.
---
---@field update fun(winid: integer, hl_group: string) # Aktualisiert die Cursorline-Hervorhebung eines Fensters auf die angegebene Highlight-Gruppe.
---
---@field mark_selected fun(bufnr: integer, ns_id: integer, line_numbers: integer[]): boolean # Markiert mehrere Zeilen als selektiert. Verwendet Buffer-Highlights innerhalb eines Namespaces. Gibt true zurück, wenn alle Markierungen erfolgreich gesetzt wurden.
---
---@field clear_marks fun(bufnr: integer, ns_id: integer): boolean # Entfernt alle gesetzten Selection-Highlights aus dem angegebenen Namespace. Gibt true zurück, wenn das Löschen erfolgreich war.

return {}
