# `lib.nvim.neotree.watch`

Neo-tree file-watcher handle registry + proactive release — a targeted fix for
the Windows file-lock that intermittently blocks renaming/deleting a directory
neo-tree is watching.

## The problem

With `use_libuv_file_watcher = true`, neo-tree opens one libuv `fs_event` handle
per expanded directory. On Windows that is an open `ReadDirectoryChangesW`
handle keeping the directory open at the OS level. Neo-tree's own `fs_watch.lua`
only ever `:stop()`s these handles — it never `:close()`s them — so the OS
handle lingers until Lua's GC runs. A rename/delete of a still-watched directory
therefore fails, non-deterministically, with `EPERM` /
`ERROR_SHARING_VIOLATION`: the watcher still holds it.

## What this does

```lua
local watch = require("lib.nvim.neotree.watch")

watch.install()          -- patch neo-tree's fs_watch (idempotent; false if absent)
watch.release(path)      -- close the handle(s) on path + every watched subpath
watch.with_release(path, fn)  -- release → fn() → release again
watch.list()             -- { path, active, exists }[], sorted — for diagnostics
watch.count()            -- how many watchers are currently tracked
```

- **`install()`** wraps `fs_watch.watch_folder` to record every watcher neo-tree
  creates (keyed by path), and wraps `stop_watching` to actually `:close()` the
  handles neo-tree would otherwise leak. It *wraps* rather than replaces, so it
  composes with any other wrapper (e.g. an EPERM-swallowing callback wrap).
- **`release(paths)`** closes the OS handle for each tracked path that is `paths`
  or a subpath of it, releasing the lock. It hands neo-tree's `Watcher` a fresh,
  *unstarted* `fs_event` afterward, so a later `updated_watched()`/`:start()`
  operates on a live handle instead of crashing on a closed one — and a fresh
  event holds nothing open until started, so the lock stays released for the
  mutation window. The watcher stays in the registry (only `stop_watching`
  forgets one for good) — neo-tree can restart the very same Watcher object on
  the same path without ever calling `watch_folder` again, and a `release`
  that forgot it there would leave a later mutation on that path with nothing
  to release, reopening the same lock.

libuv closes handles asynchronously (next loop tick), so a caller that needs the
lock gone *now* must let the event loop run before retrying — which is exactly
what `lib.nvim.cross.fs.mutate`'s `vim.wait` retry-backoff does. The intended
wiring is to drive `release` from that layer's `on_retry` hook:

```lua
local watch = require("lib.nvim.neotree.watch")
local fsops = require("lib.nvim.cross.fs.mutate")

fsops.rename_file(old, new, {
  on_retry = function() watch.release(old) end,
})
```

When nothing is installed/tracked (non-neotree setup, or the guarding feature is
off), `release` simply releases nothing — so passing the hook is always safe.

**`list()`** returns a snapshot of every tracked watcher (`path`, `active`, and
`exists` — whether `path` still exists on disk). `exists = false` is the leak
signature: a watcher still pointing at a path neo-tree never released after a
move/delete. filetree.nvim's `handle_guard` feature surfaces this via
`:Filetree handles` and its healthcheck line.

Neo-tree-specific by design (it patches a neo-tree internal), hence its home
under `lib.nvim.neotree`, alongside `node`.
