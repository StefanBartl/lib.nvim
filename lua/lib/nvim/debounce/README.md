# `lib.nvim.debounce`

Generic debounce primitive: reset a timer on every call, invoke the callback
once with the most recent arguments after the quiet period elapses. Built on
`(vim.uv or vim.loop).new_timer()`, with the callback always dispatched via
`vim.schedule` since libuv timer callbacks run off Neovim's main loop.

## Usage

```lua
local debounce = require("lib.nvim.debounce")

local d = debounce.new(function(text)
  vim.notify("saved: " .. text)
end, 300)

d.call("a")
d.call("ab") -- resets the timer; only this call's args fire
-- 300ms later: notify("saved: ab")

d.cancel() -- stop pending call; safe to call repeatedly, even if idle
```

### Buffer-scoped

`lib.nvim.debounce.buffer` keeps one independent timer per `bufnr`, and wires
a buffer-local autocmd (`BufDelete`/`BufWipeout` by default) that cancels and
forgets a buffer's timer the moment it disappears, so timers never outlive
their buffer.

```lua
local debounce_buffer = require("lib.nvim.debounce.buffer")

local d = debounce_buffer.new(function(bufnr)
  vim.notify("re-highlighted buf " .. bufnr)
end, { ms = 150, adaptive = true }) -- adaptive: larger buffers get a longer delay

d.call(bufnr)     -- (re)schedules a run for this buffer
d.cancel(bufnr)   -- cancel just this buffer's pending run
d.cancel_all()    -- cancel every tracked buffer
```

## Returns

Both `new(...)` calls return a handle table; there is no multi-value return.
