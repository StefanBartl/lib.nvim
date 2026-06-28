# lib.nvim.window

---

## Überblick

Das Modul `lib.nvim.window` bündelt kleine, fokussierte Helfer für **Overlay-
und Floating-Fenster** — also alles, was kein normales Datei-Fenster ist:
Hover-Popups, Picker, Debug-Panels, transiente Infofenster.

Statt in jedem Plugin denselben Boilerplate für Scratch-Buffer, Schließen-per-
Taste, Titel und Positionierung neu zu schreiben, ruft man hier eine kleine
Funktion auf und übergibt die Window-ID.

Leitgedanken:

* **eine Aufgabe pro Funktion** — kleine, einzeln testbare Bausteine
* **idempotent & defensiv** — ungültige IDs sind ein sicherer No-op (`pcall`,
  `nvim_win_is_valid`), nie ein Crash
* **buffer-lokal** — Keymaps und Autocmds betreffen nur das Ziel-Fenster
* **komponierbar** — `make_scratch` baut auf `nice_quit` auf; nichts wird
  doppelt implementiert

---

## Modulstruktur

```
lib.nvim.window/
├── init.lua                 -- Aggregator + attach()-Konstruktor
├── make_scratch.lua         -- Scratch-Buffer + Float in einem Call
├── nice_quit.lua            -- q / <Esc> zum Schließen (Normal-Mode)
├── set_title.lua            -- Float-Titel setzen / leeren
├── close_on_focus_lost.lua  -- Auto-Close beim Fokusverlust
├── center.lua               -- Float neu zentrieren
└── @types/                  -- LuaLS-Typen
```

Einstiegspunkt ist `require("lib.nvim.window")`. Einzelne Funktionen lassen sich
auch direkt laden (tree-shake-freundlich, in Plugin-Code empfohlen):

```lua
local make_scratch = require("lib.nvim.window.make_scratch")
```

---

## Zwei Konsum-Stile

**1) Freie Funktionen** — Window-ID jedes Mal übergeben:

```lua
local window = require("lib.nvim.window")
local winid, bufnr = window.make_scratch({ lines = { "Hallo" }, title = "Info" })
window.nice_quit(winid)
window.center(winid)
```

**2) Konstruktor (`attach`)** — gebundener Handle, **Dot-Call** (kein `self`):

```lua
local window = require("lib.nvim.window")
local w = window.attach(winid)
w.nice_quit()
w.set_title("Neuer Titel")
w.center()
```

`attach` ist reiner Zucker: jede Methode delegiert mit vorgebundener `winid` an
die freie Funktion. Die freien Funktionen bleiben die einzige Quelle der
Wahrheit.

---

## Funktionen

### `make_scratch(opts?) -> winid, bufnr`

Erzeugt einen unlisted **Scratch-Buffer** (`nofile`, `bufhidden=wipe`, kein
Swapfile) in einem **zentrierten Float** und gibt `winid, bufnr` zurück
(`nil, nil` bei Fehler — der Buffer wird dann wieder aufgeräumt).

```lua
local winid, bufnr = window.make_scratch({
  lines     = { "Zeile 1", "Zeile 2" },
  title     = "Hover",
  nice_quit = true,        -- q / <Esc> schließen sofort
  filetype  = "markdown",
})
```

| Option        | Typ                                   | Default      | Bedeutung                                              |
| ------------- | ------------------------------------- | ------------ | ------------------------------------------------------ |
| `lines`       | `string[]`                            | `{}`         | Anfangsinhalt                                          |
| `width`       | `integer`                             | Inhalt       | Breite; sonst aus Inhalt abgeleitet, auf Editor geklemmt |
| `height`      | `integer`                             | Zeilenzahl   | Höhe; auf Editor geklemmt                              |
| `relative`    | `"editor"\|"cursor"\|"win"`           | `"editor"`   | Anker des Floats                                       |
| `row` / `col` | `integer`                             | zentriert    | explizite Position (sonst Editor-Zentrierung)          |
| `border`      | `string\|string[]`                    | `"rounded"`  | Border-Stil                                            |
| `title`       | `string`                              | –            | Titel (nur mit Border sichtbar)                        |
| `title_pos`   | `"left"\|"center"\|"right"`           | –            | Titel-Position                                         |
| `focusable`   | `boolean`                             | `true`       | fokussierbar                                           |
| `enter`       | `boolean`                             | `true`       | neues Fenster sofort fokussieren                       |
| `zindex`      | `integer`                             | –            | Stapelreihenfolge                                      |
| `filetype`    | `string`                              | –            | Buffer-`filetype`                                      |
| `modifiable`  | `boolean`                             | `false`      | Buffer beschreibbar lassen (sonst Read-only)           |
| `nice_quit`   | `boolean\|NiceQuitOpts`               | `false`      | `q`/`<Esc>`-Schließen direkt verdrahten                |
| `wo`          | `table<string, any>`                  | –            | window-lokale Options-Overrides                        |
| `bo`          | `table<string, any>`                  | –            | buffer-lokale Options-Overrides                        |

Overlay-Defaults für das Fenster (`number=false`, `relativenumber=false`,
`signcolumn=no`, `wrap=false`, `cursorline=false`, `style=minimal`) sind über
`opts.wo` überschreibbar. Der Inhalt wird gesetzt, **danach** wird der Buffer
auf `nomodifiable` gelockt (außer `modifiable = true`).

---

### `nice_quit(winid, opts?) -> boolean`

Bindet `q` und `<Esc>` **buffer-lokal, nur im Normal-Mode** an das Schließen des
Fensters.

```lua
window.nice_quit(winid)
window.nice_quit(winid, { keys = { "q" }, force = true })
```

| Option  | Typ        | Default            | Bedeutung                                 |
| ------- | ---------- | ------------------ | ----------------------------------------- |
| `keys`  | `string[]` | `{ "q", "<Esc>" }` | Normal-Mode-Tasten zum Schließen          |
| `force` | `boolean`  | `false`            | ungespeicherte Änderungen verwerfen       |

**Warum nur Normal-Mode?** Dadurch entsteht das natürliche „doppelte Escape"
gratis: Der erste `<Esc>` verlässt Insert-/Terminal-Mode (Vim-Default), der
zweite `<Esc>` — jetzt im Normal-Mode — schließt das Fenster. Im Insert-/
Terminal-Mode wird nichts gemappt, damit TUI-Programme (fzf, lazygit …) Escape
weiterhin selbst erhalten. Die Keymaps nutzen `nowait`, sodass keine
`timeoutlen`-Verzögerung entsteht. Das letzte Fenster der Tabpage wird nie
geschlossen.

---

### `set_title(winid, title, opts?) -> boolean`

Setzt (oder leert mit `nil`) den Titel eines **Floating-Fensters**. Auf Nicht-
Floats ein sicherer No-op.

```lua
window.set_title(winid, "Neuer Titel", { pos = "center" })
window.set_title(winid, nil)   -- Titel entfernen
```

> **Hinweis:** Neovim speichert und zeigt einen Float-Titel nur, wenn der Float
> eine **Border** hat. Ohne Border bleibt der Titel wirkungslos (es kommt ein
> Debug-Hinweis).

---

### `close_on_focus_lost(winid, opts?) -> augroup | nil`

Registriert einen einmaligen, buffer-lokalen Autocmd, der das Fenster schließt,
sobald der Fokus es verlässt — der typische Hover-/Popup-Dismiss. Gibt die
**augroup-id** zurück, mit der man es über `nvim_del_augroup_by_id` wieder
abbestellen kann.

```lua
local grp = window.close_on_focus_lost(winid)
-- später ggf. abbrechen:
vim.api.nvim_del_augroup_by_id(grp)
```

| Option   | Typ        | Default                      | Bedeutung                        |
| -------- | ---------- | ---------------------------- | -------------------------------- |
| `events` | `string[]` | `{ "WinLeave", "BufLeave" }` | Events, die als Fokusverlust gelten |
| `force`  | `boolean`  | `true`                       | ungespeicherte Änderungen verwerfen |

Der Autocmd ist `once = true` (räumt sich selbst auf) und schließt über
`vim.schedule`, da das Schließen direkt aus `WinLeave` heraus unsicher wäre.

---

### `center(winid) -> boolean`

Zentriert ein bestehendes Float neu auf dem Editor (aus aktueller Breite/Höhe
und Editorgröße). No-op auf Nicht-Floats und ungültigen IDs.

```lua
window.center(winid)
```

---

### `attach(winid) -> Handle`

Erzeugt einen an `winid` gebundenen Handle. Alle obigen Funktionen, die `winid`
als ersten Parameter nehmen, sind als Methoden (Dot-Call) verfügbar:

```lua
local w = window.attach(winid)
w.set_title("Titel")
w.nice_quit()
w.center()
w.close_on_focus_lost()
```

---

## Typischer Ablauf

```lua
local window = require("lib.nvim.window")

local winid, bufnr = window.make_scratch({
  lines     = vim.split(hilfetext, "\n"),
  title     = " Hilfe ",
  title_pos = "center",
  filetype  = "markdown",
  nice_quit = true,            -- q / <Esc> schließen
})

window.close_on_focus_lost(winid)  -- schließt auch beim Wegklicken
```

---

## Hinweise

* Floating-spezifische Funktionen (`set_title`, `center`) haben in klassischem
  Vim kein Äquivalent; in `lib.vim.*` werden sie als not-implemented-Stub mit
  gleicher Signatur geführt (siehe [`doc/vim-parity.md`](../../../../doc/vim-parity.md)).
* Alle Funktionen sind defensiv: ungültige Window-IDs liefern einen sicheren
  Rückgabewert (`false` / `nil`) plus einen Debug-`notify`, statt zu werfen.
