# `lib.nvim.notify.safe`

Safe wrappers around `vim.notify` for *fast event contexts* — autocommand
callbacks (`TextChanged`, `CursorMoved`, `BufWritePost`, …), LSP callbacks,
and other high-frequency events where a direct `vim.notify` call can cause
errors, UI glitches, or undefined behaviour.

This submodule is re-exported as `require("lib.nvim.notify").safe`; see
[`lib.nvim.notify`](../README.md) for the full worked examples of every
function below, including `safe.create_safe`. Summary:

## Usage

```lua
local safe = require("lib.nvim.notify.safe")
-- equivalently: require("lib.nvim.notify").safe

safe.schedule("msg", vim.log.levels.INFO, {})        -- vim.schedule, next tick
safe.defer("msg", vim.log.levels.WARN, {}, 150)       -- vim.defer_fn, 150ms delay
local wrapped = safe.wrap()                            -- vim.schedule_wrap'd notify, reusable
wrapped("msg", vim.log.levels.DEBUG, {})

safe.notify("msg", vim.log.levels.INFO, {}, "schedule")  -- dispatches to schedule/defer/wrap by `mode`

local notifier = safe.create_safe("[plugin] ")
notifier.info("info message")
notifier.warn("warn message")
notifier.error("error message")
notifier.debug("debug message")
```

### `schedule(msg, level?, opts?)`

Schedules `vim.notify(msg, level, opts)` via `vim.schedule` for the next
main-loop tick. `level` defaults to `vim.log.levels.INFO`. The recommended
default for most safe call sites.

### `defer(msg, level?, opts?, delay_ms?)`

Same, but via `vim.defer_fn(..., delay_ms)` (`delay_ms` defaults to `0`).
Useful for UI transitions or manual debouncing.

### `wrap()`

Returns a `vim.schedule_wrap`-wrapped `fun(msg, level?, opts?)`, built once
and reused — the cheapest option for repeated calls from a hot path.

### `notify(msg, level?, opts?, mode?, delay_ms?)`

Convenience dispatcher: `mode` is `"schedule"` (default), `"defer"`, or
`"wrap"`, and picks which of the three functions above handles the call
(`"wrap"` builds a fresh wrapped function and invokes it once).

### `create_safe(prefix)`

Returns a notifier table (`{ notify, info, warn, error, debug }`) that
prefixes every message with `prefix` (a trailing space is appended to
`prefix` if it doesn't already end in whitespace) and always dispatches via
`schedule`. Mirrors `lib.nvim.notify.create`'s API, but fast-event-safe.
