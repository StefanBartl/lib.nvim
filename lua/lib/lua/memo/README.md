# lib.lua.memo

---

## Überblick

Das Modul `lib.lua.memo` stellt eine kleine, in sich geschlossene Caching-Infrastruktur für Neovim-Lua-Code bereit.
Der Fokus liegt auf:

* vorhersehbarem Speicherverbrauch
* konstanten Laufzeiten
* klaren, expliziten Semantiken
* einfacher Integration in bestehende `lib.*`-Hilfsmodule

Das Modul ist bewusst unabhängig von Neovim-spezifischen APIs implementiert und kann daher auch in reinem Lua-Kontext verwendet werden, eignet sich aber besonders für:

* Wrapper um teure Neovim-APIs
* Memoisierung von reinen Hilfsfunktionen
* Caching von berechneten Konfigurationen
* Reduktion von Overhead bei wiederholten `require`-ähnlichen Zugriffen

---

## Modulstruktur

```
lib.lua.memo/
├── init.lua        -- Aggregierter Export
├── lru.lua         -- LRU-Cache-Implementierung
└── memo.lua        -- Memoization auf Basis des LRU-Caches
```

Der Einstiegspunkt ist immer `require("lib.lua.memo")`.

---

## lib.lua.memo (Aggregator)

Das Top-Level-Modul bündelt die einzelnen Cache-Strategien unter einem gemeinsamen Namespace.

Verfügbare Submodule:

| Feld | Beschreibung                         |
| ---- | ------------------------------------ |
| lru  | LRU-Cache mit O(1) Zugriff           |
| memo | Memoization-Helfer auf Basis von LRU |

Beispiel:

```lua
local cache = require("lib.lua.memo")

local lru = cache.lru.new(64)
local memoize = cache.memo.memoize
```

---

## lib.lua.memo.lru

### Zweck

`lib.lua.memo.lru` implementiert einen klassischen Least-Recently-Used-Cache mit:

* O(1) Zugriff (`get`)
* O(1) Einfügen (`put`)
* deterministischem Speicherlimit
* Hashmap + doppelt verketteter Liste

Damit eignet sich der Cache besonders für:

* Funktionsresultate
* teure Berechnungen
* Normalisierungsschritte
* kleine, häufig genutzte Datensätze

---

### Datenmodell

Intern besteht der Cache aus:

* einer Map `key -> node`
* einer doppelt verketteten Liste zur Reihenfolgeverwaltung
* `head`: zuletzt verwendetes Element
* `tail`: am längsten nicht verwendetes Element

---

### API

#### new(capacity)

Erzeugt einen neuen LRU-Cache.

* `capacity` muss ≥ 1 sein
* bei Überschreiten wird automatisch das älteste Element entfernt

```lua
local LRU = require("lib.lua.memo.lru")

local cache = LRU.new(128)
```

---

#### get(key)

Liest einen Wert aus dem Cache.

* verschiebt den Eintrag an den Kopf (most-recent)
* gibt `nil` zurück, wenn der Key nicht existiert

```lua
local value = cache:get("foo")
```

---

#### put(key, value)

Speichert einen Wert im Cache.

* überschreibt vorhandene Einträge
* verschiebt den Eintrag an den Kopf
* entfernt automatisch das LRU-Element bei Overflow

```lua
cache:put("foo", 42)
```

---

## lib.lua.memo.memo

### Zweck

`lib.lua.memo.memo` stellt einen Memoization-Wrapper bereit, der auf dem LRU-Cache basiert.

Er eignet sich für:

* reine Funktionen
* deterministische Hilfsfunktionen
* Wrapper um teure Berechnungen
* Funktionen mit kleinen, primitiven Argumenten

---

### memoize(fn, cap, keyer)

Erzeugt eine memoizierte Variante einer Funktion.

Parameter:

| Parameter | Bedeutung                                   |
| --------- | ------------------------------------------- |
| fn        | zu memoizierende Funktion                   |
| cap       | maximale Cachegröße (Default: 128)          |
| keyer     | optionale Funktion zur Schlüsselgenerierung |

Standardmäßig wird der Cache-Key aus den Funktionsargumenten erzeugt.

---

#### Beispiel ohne keyer

```lua
local memo = require("lib.lua.memo.memo")

local slow_fn = memo.memoize(function(a, b)
  return a * b
end, 64)
```

---

#### Beispiel mit keyer

Empfohlen bei:

* Tabellen
* komplexen Argumenten
* nicht eindeutig stringifizierbaren Werten

```lua
local memo = require("lib.lua.memo.memo")

local fn = memo.memoize(
  function(tbl)
    return tbl.x + tbl.y
  end,
  128,
  function(tbl)
    return tbl.x .. ":" .. tbl.y
  end
)
```

---

### Einschränkungen

* Standard-Keying nutzt `table.concat({ ... })`
* Rückgabewert `nil` wird nicht gecacht
* nicht für Nebenwirkungen geeignet
* Argumente sollten deterministisch sein

---

## Typische Anwendungsfälle in Neovim

* Caching von `vim.fn.expand`, `vim.fn.resolve`
* Memoisierung von Path-Normalisierungen
* Wiederverwendung von berechneten Highlight-Definitionen
* Optimierung von LSP- oder Tree-Sitter-Hilfsfunktionen
* Wrapper um teure Lua-Pattern-Matches

---

## Designentscheidungen

* explizite Kapazitätsgrenze statt unbounded Cache
* keine Weak-Tables für maximale Vorhersagbarkeit
* kein automatisches Expiring (TTL)
* einfache, lesbare Implementierung statt Micro-Optimierung
* vollständige LuaLS-Kompatibilität

---

## Feature-Roadmap (Vorschläge)

### Kurzfristig

* `peek(key)`
  Lesen ohne Aktualisierung der LRU-Reihenfolge

* `clear()`
  Cache vollständig leeren

* `len()`
  Aktuelle Anzahl gespeicherter Einträge

---

### Mittelfristig

* optionale TTL-Unterstützung
  Zeitbasierte Invalidierung zusätzlich zur LRU-Strategie

* `invalidate(predicate)`
  Selektives Entfernen von Keys

* Statistik-API
  Hits, Misses, Evictions

---

### Langfristig

* Weak-Key / Weak-Value Varianten
  Für GC-freundliche Spezialfälle

* Shared Cache Registry
  Mehrere Memoizer teilen sich denselben LRU

* Async-/Deferred-Integration
  Kombination mit `vim.schedule` oder `vim.uv`

---

## Abgrenzung

`lib.lua.memo` ist bewusst kein generisches Datenstruktur-Framework.
Es stellt gezielt pragmatische Werkzeuge für reale Neovim-Konfigurationen bereit und ergänzt andere `lib.*`-Module wie:

* `lib.nvim.fs`
* `lib.schedule`
* `lib.nvim.require`
* `lib.nvim.notify`

---
