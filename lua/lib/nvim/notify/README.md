# `lib.nvim.notify`

## Table of content

- [`lib.nvim.notify`](#libnotify)
  - [Beispiel: Verwendung in einem Modul](#beispiel-verwendung-in-einem-modul)
  - [Beispiel: anderes Modul, anderer Prefix](#beispiel-anderes-modul-anderer-prefix)
  - [`lib.nvim.notify.safe`](#libnotifysafe)
    - [Wann wird `lib.nvim.notify.safe` benötigt](#wann-wird-libnotifysafe-bentigt)
    - [`safe.schedule`](#safeschedule)
    - [`safe.defer`](#safedefer)
    - [`safe.wrap`](#safewrap)
    - [`safe.notify`](#safenotify)
    - [`safe.create_safe(prefix)`](#safecreate_safeprefix)
    - [Empfohlene Verwendung](#empfohlene-verwendung)
  - [Eigenschaften des Designs](#eigenschaften-des-designs)

---

## Beispiel: Verwendung in einem Modul

```lua
---@module 'neotree_fs_refactor.core'

local notify = require("lib.nvim.notify").create("[neotree-fs-refactor]")

notify.info("Refactor started")
notify.warn("Some paths could not be updated")
notify.error("LSP rename failed")
```

---

## Beispiel: anderes Modul, anderer Prefix

```lua
---@module 'config.lsp.setup'

local notify = require("lib.nvim.notify").create("[lsp]")

notify.debug("Attaching server")
```

---
AUDIT: Auf englisch übersetzten und `doc/` schreiben
## `lib.nvim.notify.safe`

`lib.nvim.notify.safe` stellt sichere Wrapper um `vim.notify` bereit, die speziell für sogenannte *fast event contexts* entwickelt wurden. Dazu zählen unter anderem Callbacks aus `autocmd`s wie `TextChanged`, `CursorMoved`, `BufWritePost` oder andere hochfrequente Events, in denen ein direkter Aufruf von `vim.notify` zu Fehlern, Verzögerungen oder undefiniertem Verhalten führen kann.

Das Modul kapselt alle gängigen Schutzmechanismen (`vim.schedule`, `vim.defer_fn`, `vim.schedule_wrap`) hinter einer konsistenten, gut typisierten API.

---

### Wann wird `lib.nvim.notify.safe` benötigt

Man sollte die Safe-Varianten verwenden, wenn:

* Benachrichtigungen aus Autocommands stammen
* Benachrichtigungen aus LSP-, Tree- oder UI-Callbacks ausgelöst werden
* Code potenziell mehrfach pro Sekunde ausgeführt wird
* nicht garantiert ist, dass man sich im Haupt-Event-Loop befindet

Für normale, direkte Benutzeraktionen (Commands, Keymaps) ist weiterhin `lib.nvim.notify.create` ausreichend.

---

### `safe.schedule`

Plant die Benachrichtigung mit `vim.schedule` direkt im nächsten Main-Loop-Tick ein.
Dies ist die empfohlene Standardlösung für fast alle Safe-Fälle.

```lua
local safe = require("lib.nvim.notify").safe

safe.schedule("Scheduled notification", vim.log.levels.INFO)
```

Eigenschaften:

* sofortige, aber sichere Ausführung
* minimaler Overhead
* bevorzugte Default-Strategie

---

### `safe.defer`

Verzögert die Benachrichtigung um eine definierte Zeitspanne mittels `vim.defer_fn`.

```lua
safe.defer("Delayed warning", vim.log.levels.WARN, {}, 150)
```

Eigenschaften:

* kontrollierte Verzögerung
* nützlich bei UI-Übergängen oder Debouncing
* optionaler Delay in Millisekunden

---

### `safe.wrap`

Erzeugt eine wiederverwendbare, bereits geschedulte Notify-Funktion.
Ideal für wiederholte Aufrufe in Hotpaths.

```lua
local wrapped = safe.wrap()

wrapped("Repeated debug message", vim.log.levels.DEBUG)
```

Eigenschaften:

* effizient bei vielen Aufrufen
* vermeidet wiederholtes Erzeugen von Closures
* optimal für Schleifen oder Event-Handler

---

### `safe.notify`

Ein Convenience-Wrapper, der je nach Modus automatisch die passende Strategie wählt.

```lua
safe.notify("Auto scheduled", vim.log.levels.INFO)
safe.notify("Deferred", vim.log.levels.WARN, {}, "defer", 100)
```

Unterstützte Modi:

* `"schedule"` (Standard)
* `"defer"`
* `"wrap"`

---

### `safe.create_safe(prefix)`

Erzeugt einen sicheren Notifier mit festem Prefix, analog zu `lib.nvim.notify.create`, jedoch vollständig fast-event-safe.

```lua
local safe_notify = require("lib.nvim.notify").safe.create_safe("[plugin]")

safe_notify.info("Safe info message")
safe_notify.error("Safe error message")
```

Eigenschaften:

* Prefix wird einmal normalisiert
* identische API zu normalen Notifiern (`info`, `warn`, `error`, `debug`)
* intern immer `vim.schedule`
* keine doppelten Prefixes möglich

---

### Empfohlene Verwendung

* `lib.nvim.notify.create`
  für Commands, Keymaps, Benutzeraktionen

* `lib.nvim.notify.safe.*`
  für Autocommands, Callbacks, LSP-Events, UI-Hooks

Beide Varianten sind vollständig kompatibel und können parallel im selben Projekt eingesetzt werden.

```vim
 Standard Verwendung (wie bisher)
local notify = require("lib.nvim.notify").create("[plugin]")
notify.info("Standard notification")

-- Safe-Varianten für fast event contexts
local safe = require("lib.nvim.notify").safe

-- Variante 1: schedule (Standard)
safe.schedule("Message from fast event", vim.log.levels.INFO)

-- Variante 2: defer mit Verzögerung
safe.defer("Delayed message", vim.log.levels.WARN, {}, 100)

-- Variante 3: wrapped notifier für wiederholte Aufrufe
local wrapped_notify = safe.wrap()
wrapped_notify("Efficient repeated call", vim.log.levels.DEBUG)

-- Variante 4: Convenience wrapper
safe.notify("Auto-scheduled", vim.log.levels.INFO, {}, "schedule")

-- Variante 5: Safe notifier mit Prefix
local safe_notify = safe.create_safe("[plugin]")
safe_notify.info("Safe + prefixed")
safe_notify.error("Error from fast context")
```

---

## Eigenschaften des Designs

* ein zentrales, generisches Notify-Modul
* Prefix wird **einmal pro Datei** festgelegt
* kein doppeltes Prefixing möglich
* API identisch zu `vim.notify`
* problemlos für jede Plugin- oder Config-Komponente wiederverwendbar

---
