# `lib.lua.time.diff` – Zeitmessung mit Checkpoint-Tracking

## Table of content

- [`lib.lua.time.diff` – Zeitmessung mit Checkpoint-Tracking](#libtimediff-zeitmessung-mit-checkpoint-tracking)
  - [Übersicht](#bersicht)
  - [Statistik-Funktionen](#statistik-funktionen)
    - [Basisfunktionen](#basisfunktionen)
    - [Erweiterte Statistiken](#erweiterte-statistiken)
  - [Differenzberechnung zwischen Intervallen](#differenzberechnung-zwischen-intervallen)
    - [1. Zwischen zwei Checkpoints (Index)](#1-zwischen-zwei-checkpoints-index)
    - [2. Checkpoint gegen statistische Werte](#2-checkpoint-gegen-statistische-werte)
    - [3. Zwischen statistischen Werten](#3-zwischen-statistischen-werten)
    - [4. Mit rohen Zeitwerten](#4-mit-rohen-zeitwerten)
    - [Unterstützte Keywords](#untersttzte-keywords)
  - [Installation](#installation)
  - [Grundlegende Verwendung](#grundlegende-verwendung)
    - [1. Timer starten](#1-timer-starten)
    - [2. Checkpoints setzen](#2-checkpoints-setzen)
    - [3. Gesamtzeit abrufen](#3-gesamtzeit-abrufen)
    - [4. Intervalle zwischen Checkpoints](#4-intervalle-zwischen-checkpoints)
  - [Dynamische Properties für Checkpoints](#dynamische-properties-fr-checkpoints)
  - [Ausgabe aller Checkpoints](#ausgabe-aller-checkpoints)
    - [Standard-Format](#standard-format)
    - [Formatierte Tabelle](#formatierte-tabelle)
  - [Iterator-Unterstützung](#iterator-untersttzung)
    - [Einfacher Iterator (nur Zahlenwerte)](#einfacher-iterator-nur-zahlenwerte)
    - [Iterator mit Custom-Label](#iterator-mit-custom-label)
    - [Iterator mit Label und Index](#iterator-mit-label-und-index)
    - [Iterator mit Override-Label](#iterator-mit-override-label)
  - [Mehrere unabhängige Timer](#mehrere-unabhngige-timer)
  - [API-Referenz](#api-referenz)
    - [Methoden](#methoden)
    - [Dynamische Properties](#dynamische-properties)
  - [Fehlerbehandlung](#fehlerbehandlung)
  - [Beispiel: Benchmark einer Funktion](#beispiel-benchmark-einer-funktion)
  - [Beispiel: Iterator mit Labels](#beispiel-iterator-mit-labels)
  - [Beispiel: Erweiterte Statistiken](#beispiel-erweiterte-statistiken)
  - [Beispiel: Performance-Analyse](#beispiel-performance-analyse)
  - [Technische Details](#technische-details)
    - [Statistik-Berechnungen](#statistik-berechnungen)
    - [Variationskoeffizient (CV)](#variationskoeffizient-cv)

---

## Übersicht

Das `lib.lua.time.diff`-Modul bietet eine einfache, präzise Methode zur Messung von Zeitintervallen in Lua-Code. Es nutzt `vim.uv.hrtime()` für Nanosekundenpräzision (Standard) und ermöglicht mehrere Messpunkte innerhalb eines Zeitraums.

Jeder Aufruf von `require("lib.lua.time.diff")` erzeugt eine unabhängige Timer-Instanz mit eigenem Zustand.

**Standard-Einheit:** Nanosekunden (ns). Alle Methoden können optional eine andere Einheit (`"ms"`, `"us"`, `"s"`) akzeptieren.

## Statistik-Funktionen

Das Modul bietet umfangreiche Statistiken über die gemessenen Intervalle:

### Basisfunktionen

```lua
local diff = require("lib.lua.time.diff")

-- Mehrere Checkpoints setzen
for i = 1, 5 do
  vim.fn.sleep(math.random(50, 150))
  diff.check()
end

-- Schnellstes Intervall
print("Fastest:", diff.fastest("ms"), "ms")

-- Längstes Intervall
print("Longest:", diff.longest("ms"), "ms")

-- Durchschnittsintervall
print("Average:", diff.average("ms"), "ms")

-- Median-Intervall
print("Median:", diff.median("ms"), "ms")
```

### Erweiterte Statistiken

```lua
-- Standardabweichung
print("StdDev:", diff.stddev("ms"), "ms")

-- Variationskoeffizient (in Prozent)
print("CV:", diff.cv(), "%")
```

---

## Differenzberechnung zwischen Intervallen

Die `calc_diff()`-Funktion ist sehr flexibel und kann verschiedene Arten von Eingaben verarbeiten:

### 1. Zwischen zwei Checkpoints (Index)

```lua
local diff = require("lib.lua.time.diff")

diff.check()  -- Checkpoint 1
diff.check()  -- Checkpoint 2
diff.check()  -- Checkpoint 3

-- Differenz zwischen Checkpoint 1 und 3
local delta = diff.calc_diff(1, 3, "ms")
print("Delta:", delta, "ms")
```

### 2. Checkpoint gegen statistische Werte

```lua
-- Checkpoint 2 gegen Durchschnitt
local d1 = diff.calc_diff(2, "average", "ms")
print("Checkpoint 2 vs Average:", d1, "ms")

-- Checkpoint 1 gegen schnellstes Intervall
local d2 = diff.calc_diff(1, "fastest", "ms")
print("Checkpoint 1 vs Fastest:", d2, "ms")

-- Checkpoint 3 gegen längstes Intervall
local d3 = diff.calc_diff(3, "longest", "ms")
print("Checkpoint 3 vs Longest:", d3, "ms")

-- Checkpoint 2 gegen Median
local d4 = diff.calc_diff(2, "median", "ms")
print("Checkpoint 2 vs Median:", d4, "ms")
```

### 3. Zwischen statistischen Werten

```lua
-- Differenz zwischen schnellstem und längstem Intervall
local range = diff.calc_diff("fastest", "longest", "ms")
print("Range:", range, "ms")

-- Durchschnitt gegen Median
local diff_avg_med = diff.calc_diff("average", "median", "ms")
print("Avg vs Median:", diff_avg_med, "ms")
```

### 4. Mit rohen Zeitwerten

```lua
-- Direkter Vergleich mit Zeitwert in Nanosekunden
local target = 100000000  -- 100ms in ns
local d5 = diff.calc_diff(1, target, "ms")
print("Checkpoint 1 vs 100ms:", d5, "ms")
```

### Unterstützte Keywords

| Keyword       | Aliase          | Bedeutung                |
|---------------|-----------------|--------------------------|
| `"average"`   | `"avg"`         | Durchschnittsintervall   |
| `"fastest"`   | `"min"`         | Schnellstes Intervall    |
| `"longest"`   | `"max"`         | Längstes Intervall       |
| `"median"`    | `"med"`         | Median-Intervall         |

**Wichtig:** `calc_diff()` gibt immer den **Betrag** der Differenz zurück (positive Zahl), unabhängig von der Reihenfolge der Argumente.

## Installation

Das Modul liegt unter `lua/lib/time/diff/init.lua`. Man importiert es wie gewohnt:

```lua
local diff = require("lib.lua.time.diff")
```

---

## Grundlegende Verwendung

### 1. Timer starten

```lua
local diff = require("lib.lua.time.diff")
diff.start()  -- Startet die Zeitmessung
```

Der Timer startet automatisch beim Erstellen der Instanz. `start()` kann verwendet werden, um den Timer zurückzusetzen.

---

### 2. Checkpoints setzen

```lua
-- Code-Block 1 (Standard: Nanosekunden)
local first_diff = diff.check()
print("Erster Check:", first_diff, "ns")

-- Code-Block 2 (explizit Millisekunden)
local second_diff = diff.check("ms")
print("Zweiter Check:", second_diff, "ms")

-- Code-Block 3 (Mikrosekunden)
local third_diff = diff.check("us")
print("Dritter Check:", third_diff, "us")
```

Jeder Aufruf von `check()` gibt die verstrichene Zeit seit `start()` zurück.

**Verfügbare Einheiten:**
- `"ns"` – Nanosekunden (Standard)
- `"us"` – Mikrosekunden
- `"ms"` – Millisekunden
- `"s"` – Sekunden

---

### 3. Gesamtzeit abrufen

```lua
-- Standard: Nanosekunden
local total = diff.result()
print("Gesamtzeit:", total, "ns")

-- Explizit Millisekunden
local total_ms = diff.result("ms")
print("Gesamtzeit:", total_ms, "ms")
```

Alternativ kann man die letzte Checkpoint-Zeit direkt verwenden:

```lua
print("Total:", diff.last)  -- Immer in Nanosekunden
```

---

### 4. Intervalle zwischen Checkpoints

Man berechnet Differenzen direkt:

```lua
local delta = third_diff - first_diff
print("Zeit zwischen erstem und drittem Check:", delta, "ns")
```

Oder mit dynamischen Properties:

```lua
print("Delta:", diff.third - diff.first, "ns")
```

---

## Dynamische Properties für Checkpoints

Das Modul erzeugt automatisch Properties für alle vorhandenen Checkpoints:

| Property      | Bedeutung                                    |
|---------------|----------------------------------------------|
| `diff.first`  | Erster Checkpoint (falls vorhanden)          |
| `diff.second` | Zweiter Checkpoint (falls vorhanden)         |
| `diff.third`  | Dritter Checkpoint (falls vorhanden)         |
| `diff.fourth` | Vierter Checkpoint (falls vorhanden)         |
| ...           | Bis `tenth` (zehnter Checkpoint)             |
| `diff.last`   | Letzter Checkpoint (immer vorhanden wenn >0) |

**Wichtig:** Properties geben immer Werte in **Nanosekunden** zurück.

Beispiel:

```lua
local diff = require("lib.lua.time.diff")

diff.check()  -- Erster Checkpoint
diff.check()  -- Zweiter Checkpoint

print(diff.first)   -- Erster Checkpoint in ns
print(diff.second)  -- Zweiter Checkpoint in ns
print(diff.last)    -- Letzter Checkpoint in ns (gleich wie second)

-- Wenn nur ein Checkpoint existiert:
local diff2 = require("lib.lua.time.diff")
diff2.check()
print(diff2.first)  -- Funktioniert
print(diff2.second) -- nil (nicht vorhanden)
```

---

## Ausgabe aller Checkpoints

### Standard-Format

```lua
-- Standard: Nanosekunden
print(diff.results())
-- Ausgabe: "Check 1: 12345678ns | Check 2: 23456789ns | ... | Total: 45678901ns | Fastest: 10000000ns | Longest: 15000000ns | Average: 12500000ns | Range: 5000000ns"

-- Explizit Millisekunden
print(diff.results("ms"))
-- Ausgabe: "Check 1: 12.345ms | Check 2: 23.456ms | ... | Total: 45.678ms | Fastest: 10.000ms | Longest: 15.000ms | Average: 12.500ms | Range: 5.000ms"
```

Oder mit Metatable-Magie:

```lua
print(diff())        -- Standard: Nanosekunden
print(diff("ms"))    -- Explizit Millisekunden
```

### Formatierte Tabelle

Für bessere Lesbarkeit in `:messages` oder Notify-Fenstern:

```lua
-- Standard: Nanosekunden
print(diff.pretty())

-- Explizit Millisekunden
print(diff.pretty("ms"))
```

Beispielausgabe (Millisekunden):

```
┌────────┬─────────────────┬─────────────────┐
│ Index  │  Elapsed (ms)   │   Delta (ms)    │
├────────┼─────────────────┼─────────────────┤
│      1 │       12.345    │       12.345    │
│      2 │       23.456    │       11.111    │
│      3 │       45.678    │       22.222    │
├────────┴─────────────────┴─────────────────┤
│ Total:     45.678ms                        │
├────────────────────────────────────────────┤
│ Statistics:                                │
├────────────────────────────────────────────┤
│ Fastest Δ:       11.111ms                  │
│ Longest Δ:       22.222ms                  │
│ Average Δ:       15.226ms                  │
│ Median Δ:        12.345ms                  │
│ Range:           11.111ms                  │
│ Std Dev:          5.555ms                  │
│ CV:              36.50%                    │
└────────────────────────────────────────────┘
```

---

## Iterator-Unterstützung

Man kann sequenziell durch alle Checkpoints iterieren:

### Einfacher Iterator (nur Zahlenwerte)

```lua
diff.reset_iterator()  -- Zum Anfang zurückspringen

while true do
  local t = diff.next()  -- Standard: ns
  if not t then break end
  print("Nächster Checkpoint:", t, "ns")
end
```

### Iterator mit Custom-Label

```lua
-- Label setzen
diff.reset_iterator("Checkpoint")

while true do
  local output = diff.next(nil, "ms")  -- Mit Einheit
  if not output then break end
  print(output)  -- "Checkpoint 12.345ms"
end
```

### Iterator mit Label und Index

```lua
-- Label und Index-Anzeige aktivieren
diff.reset_iterator("Checkpoint", true)

while true do
  local output = diff.next(nil, "ms")
  if not output then break end
  print(output)  -- "Checkpoint 1: 12.345ms"
end
```

### Iterator mit Override-Label

```lua
diff.reset_iterator("Checkpoint", true)

-- Erstes next() mit Standard-Label
print(diff.next(nil, "ms"))  -- "Checkpoint 1: 12.345ms"

-- Zweites next() mit Override-Label
print(diff.next("Custom", "ms"))  -- "Custom 2: 23.456ms"

-- Drittes next() wieder mit Standard-Label
print(diff.next(nil, "ms"))  -- "Checkpoint 3: 45.678ms"
```

---

## Mehrere unabhängige Timer

Jeder `require`-Aufruf erzeugt eine neue Instanz:

```lua
local timer1 = require("lib.lua.time.diff")
local timer2 = require("lib.lua.time.diff")

timer1.start()
-- ... Code ...
timer1.check()

timer2.start()
-- ... anderer Code ...
timer2.check()

print(timer1.result())  -- Unabhängig von timer2
print(timer2.result())
```

---

## API-Referenz

### Methoden

| Methode                         | Parameter                        | Rückgabe         | Beschreibung                                      |
|---------------------------------|----------------------------------|------------------|---------------------------------------------------|
| `start()`                       | -                                | `nil`            | Startet oder setzt den Timer zurück               |
| `check(unit?)`                  | `"ns"\|"us"\|"ms"\|"s"`          | `number`         | Setzt Checkpoint, gibt Zeit seit Start zurück     |
| `result(unit?)`                 | `"ns"\|"us"\|"ms"\|"s"`          | `number\|nil`    | Gibt Gesamtzeit zurück (letzter Checkpoint)       |
| `get(idx, unit?)`               | `integer, "ns"\|"us"\|"ms"\|"s"` | `number\|nil`    | Gibt Zeit für Checkpoint `idx` zurück             |
| `next(label?, unit?)`           | `string?, "ns"\|"us"\|"ms"\|"s"` | `string\|number\|nil` | Gibt nächsten Checkpoint zurück (Iterator) |
| `reset_iterator(label?, show?)` | `string?, boolean`               | `nil`            | Setzt Iterator zurück, optional mit Label/Index   |
| `results(unit?)`                | `"ns"\|"us"\|"ms"\|"s"`          | `string`         | Erzeugt Zusammenfassung aller Checkpoints         |
| `pretty(unit?)`                 | `"ns"\|"us"\|"ms"\|"s"`          | `string`         | Erzeugt formatierte Tabelle                       |

### Dynamische Properties

| Property       | Typ             | Beschreibung                  |
|----------------|-----------------|-------------------------------|
| `first`        | `number\|nil`   | Erster Checkpoint (ns)        |
| `second`       | `number\|nil`   | Zweiter Checkpoint (ns)       |
| `third`        | `number\|nil`   | Dritter Checkpoint (ns)       |
| `fourth`-`tenth` | `number\|nil` | Vierter bis zehnter Checkpoint (ns) |
| `last`         | `number\|nil`   | Letzter Checkpoint (ns)       |

**Wichtig:** Properties geben immer Werte in Nanosekunden zurück, unabhängig von der bei `check()` gewählten Einheit.

---

## Fehlerbehandlung

Falls `check()` aufgerufen wird, ohne vorher `start()` zu nutzen:

```lua
local diff = require("lib.lua.time.diff")
-- start() wird automatisch aufgerufen, aber bei manuellem Reset:
diff.start()
diff.check()  -- OK
```

Falls eine ungültige Einheit übergeben wird:

```lua
diff.check("invalid")  -- Fehler: "Invalid unit: invalid"
```

---

## Beispiel: Benchmark einer Funktion

```lua
local diff = require("lib.lua.time.diff")

diff.start()

-- Code-Block 1
for i = 1, 1000000 do
  math.sqrt(i)
end
local t1 = diff.check("ms")

-- Code-Block 2
for i = 1, 1000000 do
  math.sin(i)
end
local t2 = diff.check("ms")

print(diff.pretty("ms"))
print("Differenz:", t2 - t1, "ms")

-- Oder mit Properties
print("Delta:", diff.second - diff.first, "ns")  -- Properties sind in ns!

-- Statistiken
print("Fastest interval:", diff.fastest("ms"), "ms")
print("Longest interval:", diff.longest("ms"), "ms")
print("Average interval:", diff.average("ms"), "ms")
```

## Beispiel: Iterator mit Labels

```lua
local diff = require("lib.lua.time.diff")

-- Drei Checkpoints setzen
for i = 1, 3 do
  vim.fn.sleep(100)
  diff.check()
end

-- Iterator mit Label und Index
diff.reset_iterator("Messung", true)

while true do
  local output = diff.next(nil, "ms")
  if not output then break end
  print(output)
  -- Ausgabe:
  -- "Messung 1: 100.123ms"
  -- "Messung 2: 200.456ms"
  -- "Messung 3: 300.789ms"
end
```

## Beispiel: Erweiterte Statistiken

```lua
local diff = require("lib.lua.time.diff")

-- Simuliere variable Ausführungszeiten
for i = 1, 10 do
  vim.fn.sleep(math.random(50, 150))
  diff.check()
end

-- Detaillierte Statistiken
print(diff.pretty("ms"))

-- Einzelne Werte abrufen
print("\nDetaillierte Analyse:")
print("Fastest:", diff.fastest("ms"), "ms")
print("Longest:", diff.longest("ms"), "ms")
print("Average:", diff.average("ms"), "ms")
print("Median:", diff.median("ms"), "ms")
print("StdDev:", diff.stddev("ms"), "ms")
print("CV:", diff.cv(), "%")

-- Differenzen berechnen
print("\nDifferenzen:")
print("Range (longest - fastest):", diff.calc_diff("fastest", "longest", "ms"), "ms")
print("Checkpoint 1 vs Average:", diff.calc_diff(1, "average", "ms"), "ms")
print("Checkpoint 5 vs Median:", diff.calc_diff(5, "median", "ms"), "ms")
```

## Beispiel: Performance-Analyse

```lua
local diff = require("lib.lua.time.diff")

-- Mehrere Operationen benchmarken
local operations = {
  "string concatenation",
  "table insertion",
  "math operations",
  "file I/O simulation"
}

for _, op in ipairs(operations) do
  -- Simuliere Operation
  for i = 1, 100000 do
    math.sqrt(i)
  end
  diff.check()
end

print(diff.pretty("us"))  -- Ausgabe in Mikrosekunden

-- Finde langsamste Operation
local longest_idx = 1
local longest_val = diff.get(1)
for i = 2, #operations do
  local val = diff.get(i)
  if val > longest_val then
    longest_idx = i
    longest_val = val
  end
end

print("\nLangsamste Operation:", operations[longest_idx])
print("Zeit:", diff.get(longest_idx, "ms"), "ms")

-- Vergleiche mit Durchschnitt
print("\nAbweichung vom Durchschnitt:")
for i, op in ipairs(operations) do
  local dev = diff.calc_diff(i, "average", "ms")
  print(string.format("%s: %+.3fms", op, dev))
end
```

---

## Technische Details

- **Präzision**: Nanosekunden (via `vim.uv.hrtime()`)
- **Standard-Einheit**: Nanosekunden (ns)
- **Verfügbare Einheiten**: `"ns"`, `"us"`, `"ms"`, `"s"`
- **Rückgabewerte**: Gleitkommazahl
- **Properties**: Immer in Nanosekunden
- **Metatable**: Unterstützt `__call` und `__tostring` für direkten Aufruf
- **Unabhängigkeit**: Jede Instanz hat eigenen Zustand
- **Dynamische Properties**: Bis zu 10 benannte Checkpoints (`first` bis `tenth`) + `last`
- **Statistiken**: Min/Max/Avg/Median/StdDev/CV werden aus Intervallen zwischen Checkpoints berechnet

### Statistik-Berechnungen

**Intervalle vs. Checkpoints:**
- Checkpoints sind kumulative Zeiten seit Start
- Intervalle sind Differenzen zwischen aufeinanderfolgenden Checkpoints
- Statistiken beziehen sich auf Intervalle (Deltas)

**Beispiel:**
```lua
-- 3 Checkpoints bei 10ms, 25ms, 50ms
diff.check()  -- Checkpoint 1: 10ms (Intervall 1: 10ms)
diff.check()  -- Checkpoint 2: 25ms (Intervall 2: 15ms)
diff.check()  -- Checkpoint 3: 50ms (Intervall 3: 25ms)

-- Statistiken beziehen sich auf Intervalle:
-- fastest = 10ms (Intervall 1)
-- longest = 25ms (Intervall 3)
-- average = (10 + 15 + 25) / 3 = 16.67ms
```

### Variationskoeffizient (CV)

Der CV gibt die relative Streuung in Prozent an:
- CV = (Standardabweichung / Mittelwert) × 100
- Niedrige Werte (< 10%): konsistente Performance
- Mittlere Werte (10-30%): moderate Variation
- Hohe Werte (> 30%): stark schwankende Performance

---
