# Entwickler-README — lib.nvim.buf_win_tab.resize_guarded

## Zweck

Dieses Modul stellt eine Hilfsfunktion bereit, um Fenstergrößen-Shortcuts (z. B. Shift+H/J/K/L)
in normalen Editoren zu ermöglichen, ohne dass diese Shortcuts in eingebetteten Terminals
oder speziellen Plugin-Puffern (z. B. lazygit) die Eingabe unterdrücken.

---

## Problemstellung

Standardmäßig überschreibt ein in Neovim gesetztes Mapping (auch im Terminal-Modus)
die eingehende Taste vollständig. Wenn das Mapping in Terminal-Buffern nur 'nichts tut'
(also early `return`), wird die Taste trotzdem nicht an den Terminalprozess weitergereicht.
Das führt z. B. dazu, dass beim Schreiben einer Commit-Meldung in lazygit die Großbuchstaben
nicht mehr erscheinen, weil `<S-h>` vom Mapping abgefangen wird.

---

## Lösungskonzept dieses Moduls

- Das Modul erzeugt eine Callback-Funktion für `vim.keymap.set`.
- Diese Callback-Funktion prüft, ob der aktuelle Buffer in einer Ausschlussliste ist
  (Dateityp oder Buffer-Name-Muster).
  - Falls ausgeschlossen: leitet das Modul die **originale Taste** an das Terminal weiter
    (mittels `nvim_replace_termcodes` + `nvim_feedkeys`) — dadurch erhält der Terminalprozess
    die echte Eingabe.
  - Falls nicht ausgeschlossen: führt das Modul den spezifizierten Resize-Befehl aus (`vim.cmd`).
- Die Originaltaste wird aus dem `lhs` abgeleitet. Für gängige Fälle (`<S-h>` etc.)
  wird automatisch der korrekte Eintrag bestimmt. Erweiterungen sind im `COMMON_FALLBACK` möglich.

---

## API

`create(cmd, exclude_filetypes?, exclude_names?, lhs?) -> function`

Parameter:
- `cmd` (string): Der auszuführende Resize-Befehl, z. B. `"vertical resize -5"`.
- `exclude_filetypes` (string[], optional): Liste von `filetype` Werten, bei denen das Mapping
  **nicht** das Resize ausführen soll (z. B. `{ "terminal" }`).
- `exclude_names` (string[], optional): Liste von Lua-Patterns, die auf `api.nvim_buf_get_name(buf)`
  angewendet werden; ein Match führt zum gleichen Verhalten wie bei `exclude_filetypes`.
- `lhs` (string, optional): Das originale Mapping-LHS, z. B. `"<S-h>"`. Wird verwendet, um die
  Taste abzuleiten, die bei ausgeschlossenen Buffern weitergereicht werden soll.

Rückgabewert:
- Eine Funktion, kompatibel mit `vim.keymap.set(..., callback)`.

---

## Beispiele

In einer Keymap-Datei:

```lua
local resize_guarded = require("lib.nvim.buf_win_tab.resize_guarded")
local exclude_filetypes = { "terminal" }
local exclude_names = { ".*lazygit.*" }

vim.keymap.set({ "n", "t" }, "<S-h>", resize_guarded.create("vertical resize -5", exclude_filetypes, exclude_names, "<S-h>"), { desc = "[Window] Resize narrower" })
vim.keymap.set({ "n", "t" }, "<S-l>", resize_guarded.create("vertical resize +5", exclude_filetypes, exclude_names, "<S-l>"), { desc = "[Window] Resize wider" })
vim.keymap.set({ "n", "t" }, "<S-k>", resize_guarded.create("resize +5", exclude_filetypes, exclude_names, "<S-k>"), { desc = "[Window] Resize taller" })
vim.keymap.set({ "n", "t" }, "<S-j>", resize_guarded.create("resize -5", exclude_filetypes, exclude_names, "<S-j>"), { desc = "[Window] Resize shorter" })
```

---

## Wichtiges technisches Detail

* Die Weiterleitung nutzt `nvim_replace_termcodes` um sicher zu stellen, dass Termcodes
  wie `<S-Left>` korrekt in Keys umgewandelt werden, und `nvim_feedkeys` um die Tasten
  wirklich an die Terminal-Subprocesse weiterzugeben.
* Die Weiterleitung verwendet die `n`-Flag (no remap) bei `nvim_feedkeys`, damit keine
  rekursiven Mappings entstehen.

---

## Erweiterungen / Anpassungen

* `COMMON_FALLBACK` kann erweitert werden, um weitere LHS → Forward-Sequenzen abzudecken.
* Falls andere Tasten (z. B. Ctrl+Shift Kombinationen oder Funktionstasten) unterstützt werden sollen,
  kann die Derivationslogik in `derive_fallback` erweitert werden.
* Falls spezielle Cases existieren (z. B. bestimmte Plugin-Buffern, die eigene Keycodes benötigen),
  können diese über `exclude_names` bzw. `exclude_filetypes` abgedeckt werden.

---

## Debugging

* Falls die Tasten in einem bestimmten Buffer weiterhin nicht durchkommen:

  1. Prüfen, ob der Buffer-Filetype wirklich in `exclude_filetypes` enthalten ist.
  2. Prüfen, ob der Buffername (`:echo bufname('%')`) gegen eines der Patterns in `exclude_names` matched.
  3. In einem Lua-REPL testen, was `derive_fallback("<S-h>")` zurückgibt, um sicherzustellen, dass
     eine Forward-Sequenz vorhanden ist.
  4. Falls nötig, temporär `print()` oder `vim.notify()` Ausgaben in der erzeugten Callback-Funktion setzen.

---

## Datei-Position

* Modul: `lua/lib/buf_win_tab/resize_guarded.lua`

-

