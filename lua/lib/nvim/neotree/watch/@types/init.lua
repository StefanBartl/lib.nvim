---@meta
---@module 'lib.nvim.neotree.watch.@types'

---A neo-tree filesystem watcher, as returned by
---`neo-tree.sources.filesystem.lib.fs_watch.watch_folder`. Only the fields this
---registry touches are described; neo-tree attaches more at runtime.
---@class Lib.Neotree.Watch.Watcher
---@field handle uv.uv_fs_event_t?  The libuv fs-event handle holding the dir open.
---@field active boolean            Whether the handle is currently :start()ed.
---@field references integer        neo-tree's own refcount for the path.

---Neo-tree file-watcher handle registry + proactive release.
---@class Lib.Neotree.Watch
---@field install       fun(): boolean                 Patch neo-tree's fs_watch; idempotent. Returns false when fs_watch is unavailable.
---@field installed     fun(): boolean                 Whether the patch is in place.
---@field release       fun(paths: string|string[]): integer  Close handles on the given paths (and any subpath). Returns how many were released.
---@field with_release  fun(paths: string|string[], fn: fun(): any): any  release → fn → release again (catch watchers re-created during fn).
---@field count         fun(): integer                 Number of watchers currently tracked (diagnostics/tests).
---@field clear         fun()                          Forget all tracked watchers without closing (tests).

return {}
