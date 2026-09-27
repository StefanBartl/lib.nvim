# `lib.nvim.echo`

Transient `nvim_echo` output — a cmdline-area line, not a popup.

`lib.nvim.notify` (optionally via `notify.popup`) is for discrete events: a
toast plus a yankable history. `lib.nvim.echo` is for the other shape of
output — a progress/status line meant to be glanced at and overwritten, the
same thing `:echo`/`:echon` are used for in Vimscript. No history, no toast,
no title: just `nvim_echo`.

```lua
local echo = require("lib.nvim.echo")

echo.write("searching... 12/128")                  -- transient, no history
echo.write("done: 128 matches", { history = true }) -- also lands in :messages
```

## `write(text_or_chunks, opts)`

- `text_or_chunks`: a plain string, or an already-built `nvim_echo` chunk list
  (`{ { "text", "HlGroup" }, ... }`) for multi-highlight lines.
- `opts.level` (a `vim.log.levels` value): only used to pick a highlight group
  when `text_or_chunks` is a plain string — `WARN` → `WarningMsg`, `ERROR` →
  `ErrorMsg`, everything else unhighlighted. Ignored for a chunk list, which
  already carries its own highlights.
- `opts.history` (default `false`): `false` calls `nvim_echo(chunks, false, {})`
  (transient, not added to `:messages`); `true` calls
  `nvim_echo(chunks, true, {})` (recorded, for a final result worth keeping).

Fast-event-safe: called from a libuv callback (a timer, an async callback), a
write is rescheduled onto the main loop instead of raising — the same reentry
guard `lib.nvim.notify.popup` uses, shared via
`lib.nvim.notify.internal.fast_event` rather than duplicated here.

## When to reach for this instead of `lib.nvim.notify`

| | `lib.nvim.notify` | `lib.nvim.echo` |
|---|---|---|
| Shape | a discrete event (success/failure/warning) | a transient status/progress line |
| History | yes (`:messages`, plus `popup`'s own history) | only if `history = true` |
| Popup/toast | optional (`popup = true`) | never — always `nvim_echo` |

`lib.nvim.output.create(prefix, { channel = "echo" })` wraps this module in
the same `info`/`warn`/`error`/`debug` shape `lib.nvim.notify.create` uses —
see `lib.nvim.output`.
