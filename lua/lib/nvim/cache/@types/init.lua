---@meta
---@module 'lib.nvim.cache.@types'

-- =========================================================
-- lib.nvim.cache.disk
-- =========================================================

---@class Lib.Cache.Opts
---@field dir? string Override the cache directory (default `stdpath("cache") .. "/lib.nvim/cache"`)

---@class Lib.Cache.SaveOpts : Lib.Cache.Opts

---@class Lib.Cache.LoadOpts : Lib.Cache.Opts
---@field ttl_seconds? integer Treat entries older than this as expired (returns `nil`, does not delete)

---@class Lib.Cache.Stats
---@field exists boolean Whether the cache file exists
---@field saved_at integer|nil Unix timestamp the entry was written, if it exists
---@field age_seconds integer|nil `os.time() - saved_at`, if it exists
---@field size_bytes integer|nil File size in bytes, if it exists

--- `lib.nvim.cache.disk` module surface: persistent JSON disk cache.
---@class Lib.Cache.Disk
---@field save fun(namespace: string, data: any, opts?: Lib.Cache.SaveOpts): boolean, string?
---@field load fun(namespace: string, opts?: Lib.Cache.LoadOpts): any
---@field clear fun(namespace: string, opts?: Lib.Cache.Opts): boolean
---@field stats fun(namespace: string, opts?: Lib.Cache.Opts): Lib.Cache.Stats

-- =========================================================
-- lib.nvim.cache.memory
-- =========================================================

---@class Lib.Cache.Memory.NamespaceOpts
---@field ttl? number Seconds an entry stays fresh (monotonic clock); omit for no TTL expiry.

---@class Lib.Cache.Memory.Stats
---@field name string
---@field hits integer
---@field misses integer
---@field invalidations integer
---@field evictions integer # TTL/tick invalidations discovered on `get`.
---@field total_requests integer
---@field hit_rate number # Percentage 0-100

--- A single namespace's accessor surface, as returned by `memory.namespace(name, opts)`.
---@class Lib.Cache.Memory.Namespace
---@field get fun(key: any, bufnr?: integer): any|nil # `bufnr` enables changedtick-based invalidation for that key.
---@field set fun(key: any, value: any, bufnr?: integer): nil
---@field invalidate fun(key: any): nil
---@field clear fun(): nil
---@field stats fun(): Lib.Cache.Memory.Stats

---@class Lib.Cache.Memory.AutoInvalidationOpts
---@field prefix? string # Augroup name (default `"lib.nvim.cache.memory"`).

--- `lib.nvim.cache.memory` module surface: generic TTL/changedtick namespace
--- cache for event handlers, with opt-in autocmd-driven auto-invalidation.
---@class Lib.Cache.Memory
---@field namespace fun(name: string, opts?: Lib.Cache.Memory.NamespaceOpts): Lib.Cache.Memory.Namespace # Create-or-get a namespace; repeat calls with the same `name` return accessors sharing one backing store.
---@field setup_auto_invalidation fun(opts?: Lib.Cache.Memory.AutoInvalidationOpts): nil # Opt-in: install TextChanged/TextChangedI (prune stale tick-bound entries) + BufWritePost (clear everything) autocmds. Idempotent.
---@field disable_auto_invalidation fun(): nil # Toggle off: remove the augroup installed by `setup_auto_invalidation`. No-op if never enabled.
---@field is_auto_invalidation_enabled fun(): boolean
---@field get_all_stats fun(): Lib.Cache.Memory.Stats[]
---@field print_all_stats fun(): nil # `print()` a formatted table of every namespace's stats; debugging aid.

-- =========================================================
-- lib.nvim.cache (aggregator)
-- =========================================================

--- Aggregator surface of `require("lib.nvim.cache")`.
---@class Lib.Cache
---@field disk Lib.Cache.Disk
---@field memory Lib.Cache.Memory

return {}
