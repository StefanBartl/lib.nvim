---@meta
---@module 'lib.nvim.frecency.@types'

---One recorded key: how often it has been chosen, and when it last was.
---Serialised exactly like this, so the on-disk form is readable and a store
---written by an older version stays loadable.
---@class Lib.Frecency.Entry
---@field count integer Number of recorded visits.
---@field last integer `os.time()` of the most recent visit.

---@class Lib.Frecency.Opts
---@field namespace string Identifies the store, and names its file. One flat, filesystem-safe identifier — it is used in the path unsanitised, exactly as `lib.nvim.cache.disk` documents for its own namespaces. Two consumers must not share one: a picker ranking file paths and a resolver ranking alternates would otherwise train each other's rankings.
---@field dir? string Parent directory (default `stdpath("data")/lib.nvim/frecency`). `stdpath("data")`, not `stdpath("cache")`: these counts are earned over months of use and cannot be regenerated, which is exactly what separates them from a cache.
---@field weight? number Multiplier applied by `lookup` (default `1.0`). Lets a consumer decide how much frecency may move a result relative to its own primary score.
---@field autoflush? boolean Register a `VimLeavePre` flush (default `true`). Off for a store the caller flushes itself, and for tests.

---A store handle. One per namespace — see `lib.nvim.frecency.store`.
---@class Lib.Frecency.Store
---@field namespace string The namespace this handle was opened for.
---@field record fun(self: Lib.Frecency.Store, key: string): nil Count a visit to `key`. In-memory; persisted by `flush`.
---@field score fun(self: Lib.Frecency.Store, key: string): number Frecency score, `0` for a key never recorded. Never touches disk after the first load.
---@field lookup fun(self: Lib.Frecency.Store, keys: string[]): table<string, number> `key -> weighted score` for exactly the keys given, omitting the ones scoring zero.
---@field flush fun(self: Lib.Frecency.Store): nil Write pending visits. No-op when nothing changed.
---@field clear fun(self: Lib.Frecency.Store): nil Forget everything, in memory and on disk.
---@field reset fun(self: Lib.Frecency.Store): nil Test-only: drop the in-memory copy so the next call re-reads from disk. Leaves the file alone.

return {}
