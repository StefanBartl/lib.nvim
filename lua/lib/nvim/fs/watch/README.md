# `lib.nvim.fs.watch`

Generic "watch this path, debounced, call me on change" primitive:
`uv.new_fs_event()` plus [`lib.nvim.debounce`](../../debounce/README.md). A
single filesystem change can fire the raw `fs_event` callback several times
in quick succession (an editor doing a save-via-rename, a build tool
touching several files at once), so the raw event feeds a debounce handle
instead of calling `on_change` directly.

## Usage

```lua
local watch = require("lib.nvim.fs.watch")

local handle, err = watch.start("/path/to/config.json", function(path, filename, events)
  vim.notify(filename .. " changed under " .. path)
end, { debounce_ms = 200 })

if not handle then
  vim.notify("watch failed: " .. err, vim.log.levels.ERROR)
end

-- later
handle.stop() -- safe to call more than once
```

## Options

| Field          | Default | Meaning                                                        |
|-----------------|---------|------------------------------------------------------------------|
| `debounce_ms`   | `200`   | Quiet period before `on_change` fires                            |
| `recursive`     | `false` | Watch subdirectories too — Linux's `inotify` backend ignores this flag entirely (libuv limitation, not this module's), so a recursive watch on Linux needs one `M.start` per subdirectory |

## Returns

| Function                          | Returns                    | Meaning                                                    |
|-------------------------------------|------------------------------|---------------------------------------------------------------|
| `M.start(path, on_change, opts)`    | `Lib.Fs.Watch.Handle\|nil, string\|nil` | A handle with `stop()`, or `nil` + error if `fs_event` setup failed |

`on_change(path, filename, events)` receives the `path` passed to `start`
(not necessarily the exact changed file — `filename` is that, when the
platform's backend reports one; it can be `nil`, and on Windows it can carry
a directory prefix such as `\0\file.txt` when the watched path is a short
8.3 path — match on the last path component), and the raw libuv
`events` table (`{change=bool, rename=bool}`).

## Start-up latency (macOS)

`start()` returns as soon as libuv accepted the handle, not once the OS
backend is delivering events. On macOS libuv registers the FSEvents stream
from its own run-loop thread, so a change made in the first milliseconds
after `start()` — most visibly under load, on the first watcher of a process —
may never be reported. Callers that must not miss such a change confirm the
watcher is live first: write a probe file until `on_change` reports it, then
make the real change (`TESTS/watch_spec.lua` does exactly that).

## Why not `lib.nvim.neotree.watch`

That module manages `fs_event` handles *neo-tree itself* creates and
starts — a handle-leak workaround, not a generic watcher. This module is
the first in the codebase to create and start an `fs_event` from scratch;
it reuses neo-tree/watch's guarded-close idiom (`is_closing()` check +
`pcall` before `:close()`, since closing is asynchronous — a handle may
still report itself open for one loop tick after `:close()`).
