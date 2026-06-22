# hover-select

hover-select ist ein kleines, modulares Neovim-Hilfsmodul zur Anzeige und Auswahl von Einträgen in einem schwebenden Fenster relativ zur Cursorposition. Es ist bewusst minimal gehalten und eignet sich als Baustein für eigene Plugins oder interne Tools.

## Table of content

  - [Motivation](#motivation)
  - [Funktionen](#funktionen)
  - [Modulaufbau](#modulaufbau)
  - [Typunterstützung](#typuntersttzung)
  - [Konfiguration](#konfiguration)
  - [Bedienung](#bedienung)
  - [Einsatzgebiet](#einsatzgebiet)

---

## Motivation

Nicht jede Auswahl in Neovim erfordert ein umfangreiches Framework wie Telescope oder fzf. Oft wird lediglich eine kompakte, kontextnahe Liste benötigt, aus der ein Eintrag gewählt werden kann. hover-select deckt genau diesen Anwendungsfall ab.

---

## Funktionen

* schwebendes Auswahlfenster relativ zum Cursor, Fenster oder Editor
* Anzeige einer einfachen String-Liste
* Callback-Funktion bei Auswahl
* klare vertikale Navigation ohne horizontale Ablenkung
* automatische Berechnung von Fenstergröße und Begrenzungen
* sauberes Ressourcen-Management über Autocommands
* eigene Hervorhebung der aktuell ausgewählten Zeile

---

### Mehrfachauswahl

#### Überblick

hover-select unterstützt nun Mehrfachauswahl über Tastenkombinationen. Benutzer können mehrere Einträge markieren, bevor sie die Auswahl bestätigen.

#### Aktivierung der Mehrfachauswahl

Setze `multi_select = true` in der Optionen-Tabelle:

```lua
hover_select.open({
  items = { "Eintrag 1", "Eintrag 2", "Eintrag 3" },
  multi_select = true,
  on_select = function(selected, indices)
    -- selected: Array der ausgewählten Einträge
    -- indices: Array der zugehörigen Zeilennummern (1-basiert)
    vim.notify("Ausgewählt: " .. table.concat(selected, ", "))
  end,
})
```

#### Tastenbelegung (Mehrfachauswahl-Modus)

| Taste | Aktion |
|-------|--------|
| `<Tab>` | Aktuelle Zeile markieren/demarkieren |
| `<S-Tab>` | Aktuelle Zeile markieren und Cursor nach oben |
| `<CR>` | Auswahl bestätigen (alle markierten Einträge oder aktuelle Zeile) |
| `<Esc>` / `q` | Schließen ohne Auswahl |

#### Änderungen an der Callback-Signatur

**Einzelauswahl-Modus** (Standard):
```lua
on_select = function(selected, index)
  -- selected: string (einzelner Eintrag)
  -- index: integer (1-basierte Zeilennummer)
end
```

**Mehrfachauswahl-Modus** (`multi_select = true`):
```lua
on_select = function(selected, indices)
  -- selected: string[] (Array von Einträgen)
  -- indices: integer[] (Array von Zeilennummern)
end
```

**Hinweis**: Wenn keine Einträge explizit mit Tab markiert wurden, gibt Enter die aktuelle Zeile als Array mit einem Element zurück.

#### Visuelle Rückmeldung

- **Cursor-Zeile**: Hervorgehoben mit `HoverSelectCursor` (verknüpft mit `PmenuSel`)
- **Markierte Zeilen**: Hervorgehoben mit `HoverSelectSelected` (verknüpft mit `Visual`)

#### Beispiel-Anwendungsfälle

**1. Dateiauswahl für Stapelverarbeitung**
```lua
local dateien = { "datei1.lua", "datei2.lua", "datei3.lua" }

hover_select.open({
  title = "Dateien zum Formatieren auswählen",
  items = dateien,
  multi_select = true,
  on_select = function(ausgewaehlte_dateien)
    for _, datei in ipairs(ausgewaehlte_dateien) do
      formatiere_datei(datei)
    end
  end,
})
```

**2. Integration mit Symbol-Gathering**
```lua
-- Nach dem Sammeln von Funktionen aus mehreren Dateien
hover_select.open({
  title = "Zu Funktionen navigieren",
  items = funktionsliste,
  multi_select = true,
  on_select = function(auswahl, indices)
    -- Alle ausgewählten Funktionen in Tabs öffnen
    for i, func in ipairs(auswahl) do
      oeffne_in_tab(func, indices[i])
    end
  end,
})
```

#### Testen

Test-Suite ausführen:
```lua
require("lib.nvim.ui.hover_select.test_multiselect").test_multi_select()
```

Verfügbare Test-Funktionen:
- `test_single_select()` - Einzelauswahl-Modus
- `test_multi_select()` - Basis-Mehrfachauswahl
- `test_multi_select_long()` - Lange Liste (20 Einträge)
- `test_file_list()` - Realistisches Dateiauswahl-Beispiel

## Modulaufbau

Das Modul ist in mehrere logisch getrennte Teile gegliedert:

* lib.nvim.ui.hover_select.buffer
  Verantwortlich für Buffer-Erstellung, Inhalt und Buffer-Optionen

* lib.nvim.ui.hover_select.window
  Fenstererstellung, Größenberechnung und Aufräumlogik

* lib.nvim.ui.hover_select.navigation
  Definition der Keymaps für Navigation, Auswahl und Schließen

* lib.nvim.ui.hover_select.highlight
  Verwaltung der Highlight-Gruppen für die Cursorzeile

* lib.nvim.ui.hover_select.config
  Zentrale Default-Werte für Buffer, Fenster und Layout

* lib.nvim.ui.hover_select.@types
  EmmyLua-Typen für Optionen und internen Zustand

---

## Typunterstützung

Über EmmyLua-Annotationen werden unter anderem folgende Typen bereitgestellt:

* Lib.HoverSelect.Options
  Konfigurationsstruktur für Items, Callback und UI-Optionen

* Lib.HoverSelect.State
  Interner Zustand mit Buffer-, Window-Referenzen und Item-Liste

Diese Typen verbessern die Arbeit mit LuaLS deutlich.

---

## Konfiguration

Standardmäßig werden folgende Aspekte vorkonfiguriert:

* Buffer als temporärer nofile-Buffer
* minimales Floating Window mit Rahmen
* deaktivierte Zeilennummern und horizontales Wrapping
* definierte Minimal- und Maximalgrößen für das Fenster

Eigene Optionen können jederzeit ergänzt oder überschrieben werden.

---

## Bedienung

* Navigation ausschließlich vertikal
* Auswahl mit Enter oder Doppelklick
* Abbrechen mit Escape oder q
* horizontale Cursorbewegungen sind deaktiviert, um Fehlbedienung zu vermeiden

---

## Einsatzgebiet

hover-select eignet sich besonders für:

* eigene Neovim-Plugins
* interne Developer-Tools
* kleine, kontextabhängige Auswahlmenüs
* Situationen, in denen maximale Kontrolle über Buffer und Window erforderlich ist

---
