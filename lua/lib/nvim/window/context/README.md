# `lib.nvim.window.context`

Window-metadata accessor with a same-event cache.

Lighter than [`lib.nvim.buffer.context`](../../buffer/context/README.md):
there is no `changedtick` for a window, so instead of validating the cache,
callers own its lifetime. Use it to avoid rebuilding the same window snapshot
from several unrelated handlers reacting to the same event; call
`clear_cache()` once that event has finished (or whenever staleness is
undesirable — e.g. from a `CursorMoved`/`WinScrolled` autocmd).

```lua
local ctx = require("lib.nvim.window.context")

local snap = ctx.get()                        -- current window, cached
if snap.is_valid and snap:is_cursor_in_range(1, 10) then
  -- snap.cursor, snap.topline, snap.botline, snap.width, snap.height
end

snap:get_visible_lines()

ctx.clear_cache()                             -- caller decides when
```

## API

| Function            | Returns                                                        |
| -------------------- | ----------------------------------------------------------------- |
| `get(winid?)`         | `Lib.Window.Context.Ctx` — cached snapshot; default is the current window |
| `clear_cache()`       | Drop every cached entry                                          |
| `invalidate(winid)`   | Drop the cached entry for one window                             |
| `get_stats()`         | `{ hits, misses, total_requests, hit_rate }`                     |
