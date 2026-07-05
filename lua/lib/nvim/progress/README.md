# lib.nvim.progress

---

## Overview

`lib.nvim.progress` abstracts "reporting on a long-running operation" away
from "how that gets shown". Plugins call `create` / `update` / `finish` /
`cancel`; a swappable **style** decides whether that becomes a `vim.notify`
call, a value your own statusline reads, a `fidget.nvim` handle, or a small
interactive floating window.

Guiding ideas:

* **one handle per operation** — no global singleton state, so concurrent
  progress indicators never collide
* **delay-guarded** — invisible until `delay_ms` (default 150ms) has
  elapsed; a fast operation never flashes UI
* **style-agnostic** — every style implements the same four-function
  contract (`start` / `update` / `finish` / `cancel`); call sites never see
  the concrete renderer
* **no hard third-party dependency** — `fidget.nvim` is only used when
  already installed (`pcall`-guarded); the `"notify"` style always works

---

## Module structure

```
lib.nvim.progress/
├── init.lua                 -- Handle: create(), delay-guard timer, cancel wiring
├── resolve_style.lua        -- "auto" -> fidget || notify ("float" is opt-in only)
├── styles/
│   ├── notify.lua           -- default: vim.notify, in-place when backend supports replace
│   ├── statusline.lua       -- headless: keeps text in memory, read via .active()
│   ├── fidget.lua           -- optional fidget.nvim adapter
│   └── float.lua            -- interactive floating window, cancel-with-confirm on <Esc>
└── @types/                  -- LuaLS types
```

---

## Usage

```lua
local progress = require("lib.nvim.progress")

local h = progress.create({ title = "[my-plugin]" })
h:update({ text = "searching", current = 12, total = 128 })
h:finish("128 matches in 19 files")
```

Cancellable operations register a callback and let the caller decide when to
trigger it — a keymap, a timeout, whatever fits:

```lua
local h = progress.create({ title = "[my-plugin]" })
h:on_cancel(function() job:kill() end)

vim.keymap.set("n", "<Esc>", function() h:request_cancel() end, { buffer = bufnr })
```

The `"float"` style wires this up for you: it opens a small, non-focus-stealing
window and only asks to cancel — via a short `vim.fn.confirm` — when *that*
window is the current buffer and `<Esc>` is pressed in normal mode. Any other
window stays completely unaffected, so the operation runs in the background
exactly like any other style, but is one buffer-focus + `<Esc>` away from a
confirmable abort:

```lua
local h = progress.create({ title = "[my-plugin]", style = "float" })
h:on_cancel(function() job:kill() end)   -- still your job to actually stop the work
```

---

## Functions

### `create(opts?) -> Handle`

| Option     | Type      | Default   | Meaning                                              |
| ---------- | --------- | --------- | ----------------------------------------------------- |
| `title`    | `string`  | `""`      | prefix shown in front of every message                |
| `style`    | `string`  | `"auto"`  | `"auto"` \| `"notify"` \| `"statusline"` \| `"fidget"` \| `"float"` |
| `delay_ms` | `integer` | `150`     | suppress the indicator until it has run this long      |
| `level`    | `integer` | `INFO`    | `vim.log.levels.*` used by the `"notify"` style        |

---

## Handle

| Method                | Effect                                                          |
| --------------------- | ---------------------------------------------------------------- |
| `h:update(fields)`    | merge `{ text, current, total }`, re-render if already visible   |
| `h:finish(text?)`     | final message, stops the indicator (silent if never shown)       |
| `h:cancel(text?)`     | final "cancelled" message, stops the indicator                   |
| `h:on_cancel(fn)`     | register a callback for `request_cancel`                         |
| `h:request_cancel()`  | mark `h.cancelled = true`, run every registered callback, then call `h:cancel()` |
| `h.cancelled`         | boolean, readable after `request_cancel`                         |

---

## Styles

| Style         | Behaviour                                                                 |
| ------------- | -------------------------------------------------------------------------- |
| `"auto"`      | prefers `"fidget"` when fidget.nvim is installed, else `"notify"`. Never picks `"float"` automatically. |
| `"notify"`    | `vim.notify`; updates replace the previous notification in place when the active backend returns a record with `.id` (e.g. nvim-notify), otherwise sequential notifies |
| `"statusline"`| headless — nothing is drawn; read `require("lib.nvim.progress.styles.statusline").active()` (`string[]`, oldest first) from your own statusline component. Calls `:redrawstatus` on every change so your component actually refreshes while you're idle, not just on the next unrelated redraw |
| `"fidget"`    | delegates to `fidget.nvim`'s LSP-style progress handles                    |
| `"float"`     | small floating window, bottom-right, `enter = false` (never steals focus); focus it and press `<Esc>` to ask for cancellation — opt-in only, see [Usage](#usage) |

Adding a new style means adding one file under `styles/` that implements
`start(spec, opts, request_cancel) -> state`, `update(state, spec, opts) -> state`,
`finish(state, spec, opts)`, `cancel(state, spec, opts)` — see
`@types/init.lua`'s `Lib.Progress.StyleImpl` for the exact shape. `request_cancel`
only matters to interactive styles like `"float"`; everything else ignores it.

---

## Notes

* Cross-platform by construction: only `vim.uv` / `vim.api` / `vim.notify`
  are used, no OS-specific calls.
* The delay-guard timer follows the same idempotent start/stop/close pattern
  as [`lib.nvim.buf_win_tab.capture`](../buf_win_tab/capture/README.md).
