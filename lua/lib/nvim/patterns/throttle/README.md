# `lib.nvim.patterns.throttle`

> Pattern: Throttle · Group: modern · Stage: `impl`

At most one call per `ms`, with optional leading and trailing calls.

## The pattern in one paragraph

Debounce waits for quiet; throttle keeps a steady rate under a constant stream of events (cursor moves, scrolling, progress). The first call of a burst runs at once (`leading`), calls during the pause are collapsed, and the latest arguments run once when the pause ends (`trailing`). Trailing calls are scheduled onto the main loop because libuv timer callbacks are unsafe for `vim.api`.

## Usage

```lua
local throttle = require("lib.nvim.patterns.throttle")

local t = throttle.new(function(line) update_preview(line) end, 100)
vim.api.nvim_create_autocmd("CursorMoved", { callback = function() t.call(vim.fn.line(".")) end })
-- t.flush() runs the pending call now, t.cancel() drops it
```

## API

| Function | Does |
| --- | --- |
| `new(fn, ms, opts)` | `opts.leading` (true), `opts.trailing` (true); returns `{ call, cancel, flush }` |

## When it helps / when it does not (Lua view)

- **Helps when:** an expensive reaction (preview, redraw) hangs off a high-frequency event and the user should still see updates while it keeps coming.
- **Does not help when:** only the final value matters; use `lib.nvim.debounce`.
- **Cheaper alternative in Lua:** a `last_run` timestamp check with `vim.uv.now()`.

## Related

- `lib.nvim.debounce`; the Index lists three hand-rolled throttles in `mdview.nvim` (`live_push`, `scroll_sync`, `selection_sync`) as the first adopters.

## Tests

`TESTS/patterns_throttle_spec.lua`: leading plus trailing with latest arguments, leading only, trailing only, flush, cancel (real timers, short intervals).
