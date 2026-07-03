# lib.nvim.buf_win_tab.capture

## Table of content

  - [Introduction](#introduction)
  - [Features](#features)
  - [Simple usage (synchronous)](#simple-usage-synchronous)
  - [Asynchronous usage](#asynchronous-usage)
  - [Multiple objects](#multiple-objects)
  - [User events (hooks)](#user-events-hooks)
  - [Why this module exists](#why-this-module-exists)
  - [Design principles](#design-principles)
  - [Conclusion](#conclusion)

---

## Introduction

Deterministic capture of buffers and windows after Ex commands in Neovim.

This module solves a core problem of the Neovim API:
there is no guarantee that after an Ex command (`:messages`, `:help`, plugin
commands) the current buffer or the current window can be unambiguously
determined.

This module uses **delta detection** plus optional polling to reliably identify
newly created UI objects.

---

## Features

- deterministic capture of new buffers and windows
- async support for UI elements created with a delay
- configurable timeouts
- multi-object detection
- persistent buffer tagging
- optional user autocommands

---

## Simple usage (synchronous)

```lua
local capture = require("lib.nvim.buf_win_tab.capture")

local result = capture.capture("messages", {
  tag = {
    buf = "messages_buffer",
    win = "messages_window",
  },
})

-- result.bufs -> list of new buffers
-- result.wins -> list of new windows
```

---

## Asynchronous usage

For commands that create UI elements with a delay:

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

## Multiple objects

The module deliberately assumes that:

* multiple buffers
* multiple windows

can be created.

Therefore it returns **lists**:

```lua
result.bufs  -- integer[]
result.wins  -- integer[]
```

---

## User events (hooks)

Optionally, a user event can be fired after a successful capture:

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

## Why this module exists

* `current_buf` and `current_win` are **not stable APIs**
* plugins like Noice, Telescope or LSP create UI asynchronously
* window and buffer types are not unambiguous

This module solves the problem via:
state comparison instead of assumptions.

---

## Design principles

* no reliance on focus
* no heuristics on `buftype` or `filetype`
* explicit state difference
* buffer identity before window focus

---

## Conclusion

With this module there is now a **general-purpose capture layer** for Neovim on
which complex UI interactions can be built reliably.

The pattern is stable, plugin-independent and future-proof.

---
