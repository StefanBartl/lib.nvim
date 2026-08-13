# Logging & notification

`lib.nvim.notify` for simple, prefixed user messages; `lib.nvim.logger` — its
richer sibling — for structured, persisted, crash-surviving diagnostics. Both
are cross-platform and have zero third-party dependencies.

## Prefixed notify factory

A per-module `vim.notify` wrapper so every plugin's messages carry a
consistent `[prefix]` instead of hand-rolled string concatenation at each
call site.

- **Module:** `lib.nvim.notify` (`create`)
- **Usage:** `local notify = require("lib.nvim.notify").create("[my-plugin]")`
  then `notify.info(...)`/`notify.warn(...)`/`notify.error(...)`/`notify.debug(...)`

```lua
local notify = require("lib.nvim.notify").create("[neotree-fs-refactor]")
notify.info("Refactor started")
notify.error("LSP rename failed")
```

## Fast-event-safe notify

`vim.notify` called directly from an autocmd, LSP callback, or any other
fast-event context can error, stall, or behave unpredictably. `notify.safe`
wraps every call in `vim.schedule`/`vim.defer_fn`/`vim.schedule_wrap` so the
same prefixed-notifier ergonomics work from anywhere.

- **Module:** `lib.nvim.notify.safe` (`schedule`, `defer`, `wrap`, `notify`, `create_safe`)
- **Usage:** `require("lib.nvim.notify").safe.create_safe("[plugin]")` — same
  `info`/`warn`/`error`/`debug` API as `notify.create`, always dispatched via
  `vim.schedule`.

Use `notify.create` for commands/keymaps (direct user actions); use
`notify.safe.*` for autocommands, LSP events, and UI callbacks.

## Structured logger

One logging strategy every plugin can adopt instead of hand-rolling its own:
prefixed levels like `notify`, plus structured `{ key = val }` context
recorded per entry, an in-memory ring-buffer history, and cross-platform
behavior throughout.

- **Module:** `lib.nvim.logger` (`new`)
- **Config:** per-instance `name`, `level` (default `"debug"`), `notify_level`
  (default `"warn"`), `file`, `capture` (default `true`), `history`, `redact`

```lua
local log = require("lib.nvim.logger").new({ name = "myplugin" })
log.info("cache warm", { entries = 128, took_ms = 12 })
log.error("write failed", { path = p, err = err })
```

`log.<level>(msg, ctx?, opts?)` — `ctx` may be a table or a thunk (only
evaluated once the level gate passes, so an expensive `ctx` costs nothing
when the level is disabled). Extras: `log.once(key, level, msg)` (log a key
at most once), `log.timer(label)` (returns a stop-closure that logs elapsed
ms), `log.assert(cond, msg, ctx)` (log + raise on falsy).

## JSONL file sink

Every logger instance can persist its records to disk as JSON Lines (one
object per line), independent of the in-memory ring buffer.

- **Module:** `lib.nvim.logger` (`file` sink)
- **Config:** `opts.file` — `nil` = `stdpath("log")/lib-logger/<name>.jsonl`
  (default), `false` = off, a `string` = explicit path

Context is sanitized before encoding: functions/userdata are stringified,
cycles are broken, depth/width are capped, and any key named in `opts.redact`
is scrubbed before it ever reaches a sink.

## Crash capture (guard/wrap + VimLeavePre flush)

Neovim has no global uncaught-error hook, so crash capture combines three
mechanisms instead of one: synchronous writes (every record is durable the
instant it's logged), an `xpcall`-based wrapper around risky functions, and
an automatic flush on exit.

- **Module:** `lib.nvim.logger` (`inst.guard`, `inst.wrap`, `capture` option)

```lua
vim.keymap.set("n", "<leader>x", log.guard(function() risky() end))  -- logs + flushes, then RE-RAISES
M.run = log.wrap(M.run, "run")                                        -- logs + flushes, then SWALLOWS
```

`capture = true` (the default) wires an automatic ring-buffer flush to the
file sink on `VimLeavePre`, so a crash on exit doesn't lose whatever was
still only in memory.

## Global and per-logger kill switches

Debug logging can be left in shipped code at de-facto zero cost: the master
switch is the very first check in the hot path, so a disabled logger costs
one boolean comparison and returns.

- **Module:** `lib.nvim.logger` (`set_enabled`, `set_level`, `disable_tag`,
  `enable_tag`, `only_tags`) — module-level (global) and per-instance
- **Usercmds:** `:LibLogger on|off`, `:LibLogger level <l>`

```lua
local L = require("lib.nvim.logger")
L.set_enabled(false)        -- global master switch
L.set_level("warn")         -- global min-level override
L.disable_tag("net")        -- drop records carrying tag "net"
L.only_tags({ "cache" })    -- whitelist mode

log.set_enabled(false)      -- per-logger override
```

## `:LibLogger` inspection command

Installed automatically the first time any plugin calls `logger.new()` —
inspect and control every registered logger from one command without each
plugin building its own debug UI.

- **Usercmds:** `:LibLogger show [n]` (recent records in a float), `:LibLogger
  on|off`, `:LibLogger level <l>`, `:LibLogger dump` (flush every logger to
  its file), `:LibLogger clear` (empty every ring buffer), `:LibLogger tags`
  (show disabled/whitelisted tags)

## Frequency counters

A lightweight tally distinct from log records — for counting how often
something happens without writing a ring-buffer entry per occurrence.

- **Module:** `lib.nvim.logger` (`inst.count(key)`, `inst.counters()`)

## Custom sinks

Attach an arbitrary function that receives every record as it's logged, for
routing log data somewhere the built-in file/notify sinks don't reach (a
telemetry endpoint, a test spy, an in-editor panel).

- **Module:** `lib.nvim.logger` (`inst.add_sink(fn)`)
