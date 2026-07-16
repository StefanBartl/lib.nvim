# `lib.nvim.cache`

Caching namespace with two independent backends:

* **`lib.nvim.cache.disk`** — persistent JSON disk cache with TTL, keyed by a
  `namespace` string. Survives Neovim restarts.
* **`lib.nvim.cache.memory`** — generic in-memory cache namespaces for event
  handlers: per-key TTL and/or buffer-changedtick validation, hit/miss/
  eviction stats, and an opt-in autocmd-driven auto-invalidation sweep. Does
  **not** survive a restart.

Neither backend touches the other; pick per call site, or use both from the
aggregator.

```
lib.nvim.cache/
├── init.lua       -- aggregator: disk, memory
├── disk.lua        -- persistent JSON disk cache
├── memory.lua       -- in-memory TTL/tick namespace cache + auto-invalidation
└── @types/        -- LuaLS types (Lib.Cache.*)
```

Entry point is `require("lib.nvim.cache")`. Individual submodules can also be
required directly (tree-shake friendly, recommended in plugin code):

```lua
local disk = require("lib.nvim.cache.disk")
local memory = require("lib.nvim.cache.memory")
```

---

## `lib.nvim.cache.disk`

Each namespace is one JSON file under
`vim.fn.stdpath("cache") .. "/lib.nvim/cache/<namespace>.json"` by default
(override the directory via `opts.dir`), storing `{ saved_at, data }`.
Namespace values are expected to be simple, filesystem-safe identifiers —
they are used directly in the file path and are not sanitized.

```lua
local disk = require("lib.nvim.cache.disk")

disk.save("github_issues", { { id = 1, title = "..." } })

local data = disk.load("github_issues", { ttl_seconds = 3600 })
-- nil if missing, unreadable, or older than ttl_seconds (file is left alone)

local stats = disk.stats("github_issues")
-- { exists = true, saved_at = 1731600000, age_seconds = 12, size_bytes = 512 }

disk.clear("github_issues")
```

| Function                | Returns                                                                 |
| ------------------------ | ------------------------------------------------------------------------ |
| `save(ns, data, opts)`   | `ok:boolean, err:string?`                                              |
| `load(ns, opts)`         | `data:any` (`nil` if missing/unreadable/expired)                       |
| `clear(ns, opts)`        | `ok:boolean` (`true` if removed or already absent)                     |
| `stats(ns, opts)`        | `{ exists, saved_at, age_seconds, size_bytes }` (all `nil` but `exists` when absent) |

---

## `lib.nvim.cache.memory`

A namespace holds an arbitrary key → value map. Values can carry a TTL
(seconds), a buffer-`changedtick` binding, or both:

```lua
local memory = require("lib.nvim.cache.memory")

local ns = memory.namespace("my_plugin.something", { ttl = 5 })

local value = ns.get(key, bufnr)  -- nil if missing, expired, or the buffer changed
if not value then
  value = expensive_compute()
  ns.set(key, value, bufnr)       -- bufnr enables changedtick invalidation
end

ns.invalidate(key)
ns.clear()
ns.stats()  -- { name, hits, misses, invalidations, evictions, total_requests, hit_rate }
```

Repeated `memory.namespace("my_plugin.something")` calls with the same name
return accessors sharing one backing store, so unrelated call sites can
cheaply agree on a namespace by name instead of passing a table reference
around. The TTL clock is monotonic (`vim.uv.hrtime`), not `os.clock()` (CPU
time) or `os.time()` (wall clock, can jump) — entries expire at a predictable
rate regardless of how idle Neovim has been or system clock changes.

### Auto-invalidation (opt-in, toggleable)

Namespaces are pure by default: creating one and calling `get`/`set` never
touches anything global. Call `setup_auto_invalidation()` to install a sweep
that keeps every namespace tidy without callers invalidating manually:

```lua
local memory = require("lib.nvim.cache.memory")

memory.setup_auto_invalidation()          -- on, using the default augroup
memory.is_auto_invalidation_enabled()     -- true

memory.disable_auto_invalidation()        -- off again
memory.is_auto_invalidation_enabled()     -- false
```

What the sweep does:

* `TextChanged` / `TextChangedI` — prune entries whose bound tick no longer
  matches the edited buffer, across every namespace.
* `BufWritePost` — clear every namespace outright.

`setup_auto_invalidation` is idempotent (safe to call again, e.g. from a
config reload — autocmds never accumulate) and accepts `{ prefix = "..." }`
to use a custom augroup name instead of the default
`"lib.nvim.cache.memory"`.

### Debugging

```lua
memory.get_all_stats()    -- Lib.Cache.Memory.Stats[]
memory.print_all_stats()  -- formatted table via print()
```
