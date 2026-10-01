# `lib.nvim.messages`

Time-stamped message/event ring buffer — the data source behind a "recent
messages" popup. No UI at all; a renderer (ui.nvim) queries it.

```lua
local messages = require("lib.nvim.messages")

messages.setup({ ring_size = 1000 })

-- Everything from the last 10 seconds, oldest first:
local recent = messages.snapshot({ since_ms = vim.uv.hrtime() / 1e6 - 10000 })

-- Live feed:
local unsubscribe = messages.on_message(function(entry)
  print(entry.kind, entry.content)
end)
messages.off_message(unsubscribe)
```

## Two feeds

1. **`lib.nvim.notify`'s own delivery pipeline** (`notify.popup`'s
   `M.deliver`) pushes every toast/history entry directly, at the source —
   not through the `ext_messages` logger below. A real-TUI spike found that
   routing notify traffic through the logger instead loses it entirely
   (neither `vim.notify` when noice owns it, nor `lib.nvim.notify` toasts,
   ever reach `ext_messages` as a `msg_show` event); writing straight into
   the store at the point of delivery is the only path that sees
   everything.
2. **`vim.ui_attach(ns, {ext_messages=true}, cb)`** — every other message
   Neovim shows (`:messages`, `:write`, search counts, Lua errors, raw
   `nvim_echo`, …). Only `history=true` `msg_show` events are kept by
   default; `config.kinds` opts a `history=false` kind in explicitly (e.g.
   `list_cmd`, `echo`, `search_cmd`). `replace_last=true` events overwrite
   the previous entry instead of appending — Neovim's own signal that this
   one updates the prior line (a search count after the pattern echo, the
   second half of a `:write` message); skipping that would double every
   search/write in the popup.

## Attach policy

Attaching as the *only* `ext_messages` listener takes over message **and**
cmdline rendering from the TUI entirely — nothing gets drawn natively, not
just "nothing recorded" (verified in a real TUI, not assumed). This module
therefore only attaches while a renderer is actually *running* — not just
installed: noice stays `require()`-able for the rest of the session after
`:Noice disable`, so `has_renderer()` checks `noice.config.is_running()`,
not module-loaded state — (or `config.renderer_override`) and detaches the
moment that stops being true.

Noice fires no enable/disable event of its own, so nothing can detect a
`:Noice disable` automatically — call `M.notify_renderer_changed()` after
toggling it yourself, or call `M.wrap_noice()` once (e.g. from setup) to
have this module patch `require("noice").enable`/`disable` and do it for
you. With no renderer at all, the `ext_messages` feed simply doesn't attach
— `M.push()` (feed 1 above) keeps working regardless.

A historical finding claimed `vim.ui_attach` could hang indefinitely if
called while any floating window was already open (a `pcall` could not
guard that, since it only catches a call that errors, not one that never
returns). Live-tested against the real config on 2026-10-01 (real TUI,
`WKDBooks/.../TOOLS/scripts/tui-spike/s7.lua`): a guard built on that
premise made this module never attach at all, since ui.nvim's own
statusline chips are themselves persistent floats open for the whole
session. Two direct `vim.ui_attach` probes in that same live session — one
with those chip floats open, one with this module's own entered/focused
popup open — both attached in under 2ms, no hang. The guard was removed;
see `maybe_attach`'s own doc comment in `init.lua` for the full writeup.

## API

- `setup(opts)` — `ring_size` (default 1000, ~0.3MB — measured negligible),
  `kinds` (`history=false` kinds to keep anyway), `renderer_override`
  (force `has_renderer()`'s answer instead of auto-detecting noice).
- `notify_renderer_changed()` — re-evaluate attach/detach now.
- `wrap_noice()` — opt-in, pcall-guarded, no-op without noice installed.
- `push(entry)` — low-level append, bypasses the `ext_messages` feed and its
  attach policy entirely. `entry.replace_last = true` overwrites the last
  entry instead of appending.
- `snapshot({since_ms, until_ms, kinds, levels})` — entries in that window,
  oldest first, as a plain copy.
- `on_message(fn)` / `off_message(fn)` — live subscription; `on_message`
  returns `fn` itself as the unsubscribe handle.

## Clock

Entries carry `time_ms` from `vim.uv.hrtime() / 1e6` — monotonic,
sub-millisecond, **not** wall-clock/epoch. `snapshot()`'s `since_ms`/
`until_ms` are the same clock. "Last N seconds" only ever needs a relative
comparison, so this sidesteps DST/epoch-rollover entirely — the trade-off is
that entries don't (and were never meant to) survive a Neovim restart; this
is a ring buffer, not a log file.
