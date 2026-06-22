# lib.lua.lazy – Wiederverwendbares Lazy-Loading für Neovim

Dieses Modul stellt einfache Hilfsfunktionen bereit, um Lua-Module in einer
Neovim-Config oder in eigenen Plugins kontrolliert und lazy zu laden.

Ziel ist es, unnötige `require()`-Aufrufe beim Startup zu vermeiden und Module
erst dann zu laden, wenn sie tatsächlich benötigt werden.

---

## Table of content

- [lib.lua.lazy – Wiederverwendbares Lazy-Loading für Neovim](#liblazy-wiederverwendbares-lazy-loading-fr-neovim)
  - [Motivation](#motivation)
    - [Lade- und Cache-Verhalten](#lade-und-cache-verhalten)
    - [Konsequenzen](#konsequenzen)
  - [API](#api)
    - [lazy.module(name)](#lazymodulename)
    - [lazy.require(name)](#lazyrequirename)
    - [lazy.fn(module, function_name)](#lazyfnmodule-function_name)
  - [Performance-Abschätzung](#performance-abschtzung)
    - [Startup](#startup)
    - [Laufzeit](#laufzeit)
  - [Sicherheit und Korrektheit](#sicherheit-und-korrektheit)
  - [Wann man es nicht einsetzen sollte](#wann-man-es-nicht-einsetzen-sollte)
  - [Typische Einsatzgebiete](#typische-einsatzgebiete)
  - [LSP-Unterstützung und Type-Annotations](#lsp-untersttzung-und-type-annotations)
  - [Fazit](#fazit)

---

## Motivation

In vielen Neovim-Konfigurationen werden Module direkt im Filescope geladen:

```lua
local mod = require("heavy.module")
```

Das bedeutet:

* das Modul wird immer beim Laden der Datei ausgeführt
* auch wenn die zugehörige Funktion nie benutzt wird
* Startup-Zeit und Speicherverbrauch steigen mit der Config-Größe

`lib.lua.lazy` erlaubt es, dieses Verhalten explizit zu kontrollieren.

### Lade- und Cache-Verhalten

In Lua gilt:
* `require()` lädt immer das komplette Modul
* das Modul wird exakt einmal ausgeführt
* das Rückgabeobjekt wird in `package.loaded[name]` gespeichert
* alle definierten Funktionen werden erzeugt
* ungenutzte Funktionen bleiben dennoch im Speicher

Ablauf:
1. `require("notify")` wird aufgerufen
2. Lua sucht das Modul anhand von `package.searchers`
3. die Datei wird vollständig gelesen
4. der gesamte Top-Level-Code wird ausgeführt
5. alle Funktionen werden erstellt
6. das Rückgabeobjekt wird gecacht
7. zukünftige `require()`-Aufrufe liefern nur die Referenz

Wichtig:
* Lua kennt kein partielles Laden von Modulen
* es existiert kein automatisches Tree Shaking
* selbst wenn nur `warn()` genutzt wird, werden `info()`, `debug()` usw. ebenfalls erzeugt

---

### Konsequenzen

* Seiteneffekte im Top-Level-Code werden immer ausgeführt
* Initialisierungskosten fallen vollständig beim ersten `require()` an
* Moduldesign sollte initialisierungsarm sein
* Lazy Loading muss manuell implementiert werden

---

## API

### lazy.module(name)

Erzeugt einen Lazy-Wrapper für ein Modul.

```lua
local lazy = require("lib.lua.lazy")
local mymod = lazy.module("mymodule")

mymod.get().do_work()
```

Eigenschaften:

* `require()` wird exakt einmal ausgeführt
* Ergebnis wird in einem Upvalue gecached
* nach dem ersten Zugriff minimaler Overhead (Nil-Check)

**Hinweis zur LSP-Unterstützung:**

Bei Verwendung von `lazy.module()` erhält man ein Wrapper-Objekt vom Typ `Lib.LazyModule`, nicht das eigentliche Modul. Das bedeutet:

* Keine automatische Type-Inference für das geladene Modul
* Keine Autocompletion für Modul-Funktionen bis `.get()` aufgerufen wird
* Man muss den Typ nach `.get()` manuell annotieren

```lua
local mymod_lazy = lazy.module("mymodule")

-- Kein LSP-Support hier:
-- mymod_lazy ist vom Typ Lib.LazyModule

---@type MyModule.Type
local mymod = mymod_lazy.get()

-- Jetzt hat man LSP-Support:
mymod.do_work()
```

Für bessere LSP-Unterstützung siehe `lazy.require()`.

---

### lazy.require(name)

Erzeugt ein lazy-geladenes Modul mit direkter Type-Inference-Unterstützung.

```lua
local lazy = require("lib.lua.lazy")

---@type MyModule.Type
local mymod = lazy.require("mymodule")

-- Volle LSP-Unterstützung ab hier:
mymod.do_work()
```

Eigenschaften:

* `require()` wird exakt einmal ausgeführt (beim ersten Zugriff auf das Modul)
* Ergebnis wird gecacht
* Rückgabe ist das Modul selbst, nicht ein Wrapper
* Vollständige LSP-Unterstützung durch Type-Annotation

**Unterschied zu `lazy.module()`:**

* `lazy.module()` gibt ein Wrapper-Objekt zurück (Typ: `Lib.LazyModule`)
* `lazy.require()` gibt das tatsächliche Modul zurück (castbar auf jeden Typ)
* `lazy.require()` ist die empfohlene Variante für Module mit komplexer API

**Verwendung mit Type-Annotations:**

```lua
---@type WkdNvC.UI.Stl.Modules.LSP.Cfg.Module
local config_mod = lazy.require("wkdnvchad.ui.statusline.modules.lsp.config")

-- LSP kennt jetzt alle Funktionen:
local options = config_mod.get_cfg()
config_mod.set("debounce_ms", 500)
```

**Technischer Hintergrund:**

`lazy.require()` nutzt intern `lazy.module()`, gibt aber direkt das Ergebnis von `.get()` zurück. Die `---@diagnostic disable-next-line: return-type-mismatch` Annotation im Modul erlaubt es dem Language Server, den Generic-Type `T` anzunehmen, der durch die Type-Annotation am Call-Site definiert wird.

---

### lazy.fn(module, function_name)

Erzeugt einen lazy geladenen Funktions-Wrapper.

```lua
local lazy = require("lib.lua.lazy")
local do_work = lazy.fn("mymodule", "do_work")

do_work(42)
```

Eigenschaften:

* `require()` läuft beim ersten Aufruf
* danach wird die Funktion neu gebunden
* kein weiterer Lazy-Check im Hot-Path

Diese Variante ist aggressiver und nur für Performance-kritische Pfade gedacht.

---

## Performance-Abschätzung

### Startup

* kein Laden des Moduls beim Start
* weniger Lua-Bytecode
* weniger Initialisierung von Nebenlogik (Autocommands, Caches)

### Laufzeit

* `lazy.module`:
  * ein einfacher Nil-Check pro Zugriff
  * vernachlässigbarer Overhead für die meisten Use-Cases
* `lazy.require`:
  * identisch mit `lazy.module` (nutzt intern dasselbe Caching)
  * kein Performance-Unterschied
* `lazy.fn`:
  * nach dem ersten Aufruf keinerlei Zusatzkosten

Im Vergleich zu eager `require()` ist der Gesamteffekt in großen Configs
spürbar positiv, besonders bei vielen optionalen Features.

---

## Sicherheit und Korrektheit

* `require()` wird nicht umgangen, sondern nur verzögert
* Lua-Standard-Caching (`package.loaded`) bleibt vollständig erhalten
* Fehler im Modul treten beim ersten Zugriff auf, nicht stillschweigend
* keine globale Mutation, nur lokale Upvalues

Das Verhalten ist deterministisch und reproduzierbar.

---

## Wann man es nicht einsetzen sollte

* bei sehr kleinen Utility-Modulen
* bei Funktionen, die auf jedem Keypress laufen
* bei Code, der bewusst beim Startup Seiteneffekte erzeugen soll

Lazy-Loading ist ein Werkzeug, kein Dogma.

---

## Typische Einsatzgebiete

* Feature-spezifische Logik
* Event-Handler
* Neo-tree / LSP / Git-Integrationen
* eigene Plugins mit optionalen Komponenten

---

## LSP-Unterstützung und Type-Annotations

Für optimale LSP-Unterstützung mit Autocompletion und Type-Checking gibt es mehrere Ansätze:

### Variante 1: lazy.require mit Type-Annotation (empfohlen)

```lua
---@type MyModule.Type
local mymod = lazy.require("mymodule")
```

Vorteile:
* Direkte LSP-Unterstützung
* Keine Wrapper-Indirektion
* Einfachste Syntax

### Variante 2: lazy.module mit manuellem Cast

```lua
local mymod_lazy = lazy.module("mymodule")

---@type MyModule.Type
local mymod = mymod_lazy.get()
```

Vorteile:
* Explizite Trennung von Lazy-Wrapper und Modul
* Nützlich wenn man den Lazy-Wrapper selbst weitergeben will

### Variante 3: Inline-Cast bei lazy.module

```lua
---@type MyModule.Type
local mymod = lazy.module("mymodule").get()
```

Nachteile:
* Kann zu Type-Mismatch-Warnungen führen
* Erfordert möglicherweise `---@diagnostic disable-next-line`

### Type-Definitionen erstellen

Für eigene Module sollte man Type-Definitionen in `@types` Ordnern anlegen:

```lua
---@meta
---@module 'mymodule.@types'

---@class MyModule.Type
---@field do_work fun(n: integer): string
---@field get_config fun(): MyModule.Config

---@class MyModule.Config
---@field timeout integer
---@field retry boolean

return {}
```

Diese Types können dann bei `lazy.require()` oder `lazy.module()` verwendet werden.

---

## Fazit

`lib.lua.lazy` hilft dabei, Neovim-Konfigurationen:

* strukturierter
* performanter
* besser skalierbar

zu gestalten, ohne komplexe Infrastruktur oder externe Abhängigkeiten.

Die Wahl zwischen `lazy.module()` und `lazy.require()` hängt vom Use-Case ab:

* **`lazy.module()`**: Wenn man explizit mit dem Lazy-Wrapper arbeiten will
* **`lazy.require()`**: Für direkten Zugriff mit optimaler LSP-Unterstützung (Standard-Fall)
* **`lazy.fn()`**: Für einzelne Funktionen in Hot-Paths

---
