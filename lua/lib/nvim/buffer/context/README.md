# `lib.nvim.buffer.context`

Buffer-metadata accessor cached by `changedtick`.

Building a buffer snapshot (name, filetype, line count, ...) touches several
`nvim_buf_*` calls; callers that ask for it repeatedly within the same
"version" of a buffer — e.g. once per keystroke from several unrelated
autocmd handlers reacting to the same event — would otherwise redo that work
every time. `get()` keys its cache on the buffer's `changedtick`, so repeated
calls between edits are free.

```lua
local ctx = require("lib.nvim.buffer.context")

local snap = ctx.get()               -- current buffer, cached
if snap.is_valid and snap:is_normal() then
  -- snap.filetype, snap.buftype, snap.modifiable, snap.modified, ...
end

snap:has_filetype("lua")             -- string or string[]
snap:is_processable({ "nofile" }, { "help" })  -- ignore_buftypes, ignore_filetypes

snap.lines                           -- lazy-loaded on first access, then cached
```

## API

| Function            | Returns                                                        |
| -------------------- | ----------------------------------------------------------------- |
| `get(bufnr?)`         | `Lib.Buffer.Context.Ctx` — cached snapshot; default is the current buffer |
| `invalidate(bufnr)`   | Drop the cached entry for one buffer                            |
| `clear_all()`         | Drop every cached entry                                          |
| `get_stats()`         | `{ hits, misses, invalidations, total_requests, hit_rate }`      |
| `print_stats()`       | `print()` a formatted stats table (debugging aid)                |

The cache is weak-keyed (`bufnr -> snapshot`), so entries for deleted buffers
are collected automatically; `invalidate`/`clear_all` exist for callers that
want to force a rebuild sooner (e.g. after mutating a buffer through a path
that does not bump `changedtick`).

See also [`lib.nvim.window.context`](../../window/context/README.md) for the
window-side equivalent.
