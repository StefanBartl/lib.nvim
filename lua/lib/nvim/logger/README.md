# `lib.nvim.logger`

Structured logging, diagnostics and crash dumps — a richer sibling of
[`lib.nvim.notify`](../notify/README.md). One logging strategy every plugin can
adopt instead of hand-rolling its own. All cross-platform.

```lua
local log = require("lib.nvim.logger").new({ name = "myplugin" })

log.info("cache warm", { entries = 128, took_ms = 12 })
log.error("write failed", { path = p, err = err })
```

## What it adds over `notify`

| | `notify` | `logger` |
| --- | --- | --- |
| Prefixed `info/warn/error/debug` | ✅ | ✅ (via its notify sink, fast-event safe) |
| Structured context `{ key = val }` | ✗ | ✅ recorded per entry |
| In-memory history (bounded ring) | ✗ | ✅ `history` records |
| Persist to a file (JSONL) | ✗ | ✅ `file` sink |
| Dump on crash | ✗ | ✅ `guard`/`wrap` + `VimLeavePre` flush |
| Turn off with ~zero cost | ✗ | ✅ global/per-logger/level/tag switches |

`notify` is unchanged and still the right tool for a simple user-facing
message; `logger` composes it.

## Creating a logger

```lua
local log = require("lib.nvim.logger").new({
  name         = "myplugin",  -- scope / prefix
  level        = "debug",     -- min level to RECORD (default "debug")
  notify_level = "warn",      -- min level to also vim.notify (default "warn")
  file         = nil,         -- nil = stdpath default, false = off, string = path
  capture      = true,        -- flush ring on VimLeavePre (default true)
  history      = 200,         -- ring-buffer size
  redact       = { "token" }, -- context keys to scrub before any sink
})
```

Levels accept a number (`vim.log.levels`) or a name: `"trace"`, `"debug"`,
`"info"`, `"warn"`, `"error"`, `"off"`.

## Logging

```lua
log.info("cache warm", { entries = 128 })
log.debug("state", function() return expensive() end)  -- thunk: only runs when active
log.warn("tagged", { x = 1 }, { tags = { "net" } })    -- per-call opts
log.error("boom", { err = e })                          -- durable immediately

-- extras
log.once("startup", "info", "initialised")   -- log a key at most once
local stop = log.timer("index build"); stop({ files = 42 })  -- logs elapsed ms
log.assert(cond, "must hold", ctx)            -- log + raise on falsy
```

`log.<level>(msg, ctx?, opts?)`. `ctx` is a table or a function returning one
(deferred until after the level gate). `opts`: `tags`, `to` (per-call file
override), `notify` (force/suppress the notify for this call).

## Switches — turn logging off with de-facto zero cost

```lua
local L = require("lib.nvim.logger")

L.set_enabled(false)        -- global master switch (one comparison when off)
L.set_level("warn")         -- global min-level override; nil clears
L.disable_tag("net")        -- drop records carrying tag "net"
L.only_tags({ "cache" })    -- whitelist mode; nil clears

log.set_enabled(false)      -- per-logger
log.set_level("error")
```

The master switch is checked first in the hot path, so a disabled logger does a
single boolean check and returns — leave debug logging in shipped code.

## Crash capture

Neovim has no global uncaught-error hook, so capture combines three mechanisms
(see [`../../../../doc/lib.nvim-logger.txt`](../../../../doc/lib.nvim-logger.txt)):

```lua
-- 1) synchronous writes -> every record is durable immediately
-- 2) guard/wrap: log a traceback + flush, then re-raise (guard) or swallow (wrap)
vim.keymap.set("n", "<leader>x", log.guard(function() risky() end))
M.run = log.wrap(M.run, "run")
-- 3) VimLeavePre flush (automatic when capture=true and a file sink is set)
```

`log.flush()` / `log.snapshot()` / `log.clear()` operate on the ring buffer.

## File sink

Appends JSONL (one JSON object per line). Default:
`stdpath("log")/lib-logger/<name>.jsonl`. Context is sanitized before encoding
(functions/userdata stringified, cycles broken, depth/width capped, redacted
keys scrubbed).

## `:LibLogger` command

Installed on the first `logger.new()`:

```
:LibLogger show [n]   recent records in a float
:LibLogger on|off     global enable / disable
:LibLogger level <l>  set global min level
:LibLogger dump       flush every logger to its file
:LibLogger clear      empty every ring buffer
:LibLogger tags       show disabled / whitelisted tags
```
