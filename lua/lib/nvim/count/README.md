# `lib.nvim.count`

Helpers for count-prefixed keymaps (`3<leader>xy`).

Reading `vim.v.count` is a three-way decision, and the wrong branch is easy to
pick by accident:

| You want | Use | Why |
| --- | --- | --- |
| "no count means once" | `get()` (`vim.v.count1`) | Never 0. Right for motions, cycles, next/prev. |
| 0 has its own meaning | `raw()` (`vim.v.count`) | e.g. no count → half a window height. |
| the count indexes something bounded | `clamp(min, max)` | An out-of-range count must not reach the caller. |

```lua
local count = require("lib.nvim.count")

-- next/prev: 3<leader>in = 3 items forward
map("n", "<leader>in", function() nav.next(count.get()) end)

-- heading depth 1..9
map("n", "+", function() browse.set_depth(count.clamp(1, 9)) end)

-- 0 means "half a window"
map("n", "<C-d>", function()
  local n = count.raw()
  scroll(n == 0 and math.floor(vim.api.nvim_win_get_height(0) / 2) or n)
end)
```

## Repeating an action

Two ways, and the difference matters.

### `times(fn, opts)` — synchronous

Runs `fn(i)` once per count. Only correct when `fn` finishes before it could be
called again. Return `false` from `fn` to stop early at a boundary:

```lua
count.times(function()
  return cycle.navigate(1)   -- false at the end of the list -> stop
end)
```

Returns how many times it actually ran. Capped at `count.DEFAULT_MAX` (1000)
unless you pass `max` — a typed count can be fat-fingered.

### `chain(opts)` — gated on a completion signal

For actions that complete *later*, via an event rather than a return: a
debug-adapter step, a request/response round trip, a queued fetch. Firing the
second call while the first is still in flight is the bug this prevents — with
DAP it is an outright protocol violation.

Generalized from dap.nvim's `counted_step()`.

```lua
count.chain({
  action = dap.step_over,
  subscribe = function(advance, abort)
    local key = "myplugin.step_over"
    dap.listeners.after.event_stopped[key]    = advance
    dap.listeners.after.event_terminated[key] = abort
    dap.listeners.after.event_exited[key]     = abort
    return function()
      dap.listeners.after.event_stopped[key]    = nil
      dap.listeners.after.event_terminated[key] = nil
      dap.listeners.after.event_exited[key]     = nil
    end
  end,
})
```

`subscribe` gets two callbacks and returns an unsubscribe:

- `advance` — call it when one unit of work has completed.
- `abort` — call it when the thing being driven went away. The chain is
  dropped and the listeners are removed, so nothing dangles waiting for a
  signal that will never arrive.

With no count — the overwhelmingly common case — `action` is called directly,
`subscribe` is never invoked, and there is nothing to clean up. `chain` returns
`false` in that case, `true` when it actually set up a chain.

If `subscribe` is missing or raises, `chain` reports it and runs the action
*once*. It deliberately does not fall back to a synchronous loop: that loop is
the unsafe thing it exists to avoid.

## Notes

- `times` and `chain` both accept an explicit `count` in `opts`, which makes
  them testable without a real keypress.
- Nothing here registers keymaps. Pair it with `lib.nvim.map`.
