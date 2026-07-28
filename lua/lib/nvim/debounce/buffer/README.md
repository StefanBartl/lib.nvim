# `lib.nvim.debounce.buffer`

Buffer-scoped debounce: one independent timer per `bufnr`, built on top of
[`lib.nvim.debounce`](../README.md)'s single-timer primitive.

## Usage

```lua
local debounce_buffer = require("lib.nvim.debounce.buffer")

local d = debounce_buffer.new(function(bufnr)
  vim.notify("re-highlighted buf " .. bufnr)
end, { ms = 150, adaptive = true })

d.call(bufnr)     -- (re)schedules a run ~150ms out for this buffer
d.cancel(bufnr)   -- cancel just this buffer's pending run
d.cancel_all()    -- cancel every tracked buffer
```

`d.call(bufnr, ...)` resets that buffer's timer; when it fires, `fn(bufnr,
...)` runs with the arguments from the *most recent* call for that buffer,
dispatched via `vim.schedule` (libuv timer callbacks run off Neovim's main
loop).

A buffer-local autocmd on `opts.cleanup_events` (default `BufDelete`,
`BufWipeout`) is armed on a buffer's first `call` and cancels/forgets that
buffer's timer the moment it fires, so timers never outlive their buffer.

## Options — `opts`

| Field             | Type       | Default                       | Meaning |
|-------------------|------------|--------------------------------|---------|
| `ms`              | `integer`  | `200`                          | Base delay in milliseconds. |
| `adaptive`        | `boolean`  | `false`                        | Scale the delay with the buffer's line count (see below). |
| `cleanup_events`  | `string[]` | `{ "BufDelete", "BufWipeout" }` | Autocmd events that cancel a buffer's timer. |

When `adaptive` is set, the effective delay is
`min(ms * 4, ms + floor(line_count / 50))` — debouncing large buffers (e.g.
for expensive highlighting) backs off automatically instead of firing on the
base delay regardless of buffer size.

## Returns

`new(fn, opts)` returns a handle `{ call, cancel, cancel_all }`; there is no
multi-value return.
