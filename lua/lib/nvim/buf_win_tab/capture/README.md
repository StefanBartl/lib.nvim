# lib.nvim.buf_win_tab.capture

## Table of content

  - [Einleitung](#einleitung)
  - [Features](#features)
  - [Einfache Nutzung (synchron)](#einfache-nutzung-synchron)
  - [Asynchrone Nutzung](#asynchrone-nutzung)
  - [Mehrere Objekte](#mehrere-objekte)
  - [User-Events (Hooks)](#user-events-hooks)
  - [Warum dieses Modul existiert](#warum-dieses-modul-existiert)
  - [Designprinzipien](#designprinzipien)
  - [Fazit](#fazit)

---

## Einleitung

Deterministisches Erfassen von Buffern und Windows nach Ex-Commands in Neovim.

Dieses Modul löst ein zentrales Problem der Neovim-API:
Es gibt keine Garantie, dass nach einem Ex-Command (`:messages`, `:help`, Plugin-Commands)
der aktuelle Buffer oder das aktuelle Window eindeutig bestimmbar ist.

Dieses Modul verwendet **Delta-Erkennung** plus optionales Polling,
um neu erzeugte UI-Objekte zuverlässig zu identifizieren.

---

## Features

- deterministisches Erfassen neuer Buffer und Windows
- Async-Support für verzögert erzeugte UI-Elemente
- konfigurierbare Timeouts
- Mehrfach-Objekt-Erkennung
- persistentes Buffer-Tagging
- optionale User-Autocommands

---

## Einfache Nutzung (synchron)

```lua
local capture = require("lib.nvim.buf_win_tab.capture")

local result = capture.capture("messages", {
  tag = {
    buf = "messages_buffer",
    win = "messages_window",
  },
})

-- result.bufs -> Liste neuer Buffer
-- result.wins -> Liste neuer Windows
```

---

## Asynchrone Nutzung

Für Commands, die UI-Elemente verzögert erzeugen:

```lua
capture.capture("SomeAsyncCommand", {
  timeout = 500,
}, function(result)
  for _, win in ipairs(result.wins) do
    vim.api.nvim_set_current_win(win)
  end
end)
```

---

## Mehrere Objekte

Das Modul geht bewusst davon aus, dass:

* mehrere Buffer
* mehrere Windows

entstehen können.

Deshalb werden **Listen** zurückgegeben:

```lua
result.bufs  -- integer[]
result.wins  -- integer[]
```

---

## User-Events (Hooks)

Optional kann nach erfolgreichem Capture ein User-Event ausgelöst werden:

```lua
capture.capture("messages", {
  emit_event = true,
})
```

Listener:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "BufWinCapture",
  callback = function(ev)
    local data = ev.data
    -- data.bufs
    -- data.wins
  end,
})
```

---

## Warum dieses Modul existiert

* `current_buf` und `current_win` sind **keine stabilen APIs**
* Plugins wie Noice, Telescope oder LSP erzeugen UI asynchron
* Window- und Buffer-Typen sind nicht eindeutig

Dieses Modul löst das Problem durch:
Zustandsvergleich statt Annahmen.

---

## Designprinzipien

* kein Vertrauen in Fokus
* keine Heuristiken auf `buftype` oder `filetype`
* explizite Zustandsdifferenz
* Buffer-Identität vor Window-Fokus

---

## Fazit

Mit diesem Modul existiert nun eine **allgemeingültige Capture-Schicht** für Neovim,
auf der sich zuverlässig komplexe UI-Interaktionen aufbauen lassen.

Das Pattern ist stabil, plugin-unabhängig und zukunftssicher.

---
