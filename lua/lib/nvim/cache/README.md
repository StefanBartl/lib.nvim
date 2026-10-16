# `lib.nvim.cache`

Caching namespace with two independent backends (plus the per-call `invocation` cache, below):

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
├── invocation.lua   -- per-call cache (`run`/`memo`) and the editor-state reader
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

local data, err = disk.load("github_issues", { ttl_seconds = 3600 })
-- nil if missing, unreadable, or older than ttl_seconds (file is left alone);
-- `err` is nil for missing/expired and set when a file exists but could not
-- be read ("read failed: …") or decoded ("invalid json: …")

local stats = disk.stats("github_issues")
-- { exists = true, saved_at = 1731600000, age_seconds = 12, size_bytes = 512 }

disk.clear("github_issues")
```

| Function                | Returns                                                                 |
| ------------------------ | ------------------------------------------------------------------------ |
| `save(ns, data, opts)`   | `ok:boolean, err:string?`                                              |
| `load(ns, opts)`         | `data:any, err:string?` (`data` is `nil` if missing/unreadable/expired; `err` only for an existing file that failed to read or decode — a load-modify-save caller uses it to not overwrite real data with its empty default) |
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

Nothing is garbage-collected on its own. An entry under a string key (the
usual case) lives until its TTL runs out, `invalidate`/`clear` drops it, or
the opt-in sweep below removes it — a namespace without `ttl` and without the
sweep keeps one value per distinct key for the whole session. Namespaces
themselves are never removed either, so mint them from a fixed set of names,
not from per-call data.

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
memory.format_stats()     -- the same table as string[] (header, one row per namespace, total)
memory.print_all_stats()  -- formatted table via print()
```

`ns.stats()` / `get_all_stats()` also report `entries`: the entries a namespace holds now (an expired one
stays counted until a `get`, a sweep or `invalidate` evicts it).

`:Lib cache stats` (registered by `lib.nvim_usrcmds`, through `cache.routes()`) shows that table for every
namespace of every plugin that uses `lib.nvim.cache.memory`.

## `lib.nvim.cache.invocation`

A cache that lives for **one call**. Inside `scope:run(fn)` a value computed by `scope:memo(key, produce)` is
remembered until the outermost `run` returns (or raises), then dropped; outside a `run` nothing is remembered and
`produce()` is simply called. Each scope keeps its values in a table of its own, so they are not touched by
`lib.nvim.cache.memory`'s auto-invalidation and do not appear in `:Lib cache stats`.

**A run belongs to the coroutine that started it.** `fn` may yield: after the resume it still sees its values, while
the main thread and other coroutines neither see them nor end them. A coroutine spawned inside a run does not share
the values either (its `memo` calls through).

Use it when nested helpers of one command must see ONE reading of the editor without a table being passed
through every signature (generalised from open.nvim's `context.with_cache`).

```lua
local scope = require("lib.nvim.cache.invocation").new("open")

scope:run(function()
  local state = scope:editor_state()   -- reads the editor once ...
  local again = scope:editor_state()   -- ... the same table here, however deep the call
  local root = scope:memo("git_root", function() return find_root() end)
end)
```

| Function                    | Returns                                                                                       |
| --------------------------- | --------------------------------------------------------------------------------------------- |
| `new(name)`                 | a scope; two scopes never share values, even with the same name                               |
| `scope:run(fn, ...)`        | `fn`'s results; nested runs share the outer values; an error is re-raised unchanged (level 0) |
| `scope:memo(key, produce)`  | the cached value (`key` is a string; `nil`/`false` are cached too); a raising producer stores nothing |
| `scope:active()`            | whether a `run` is in progress                                                                |
| `scope:editor_state()`      | `read_editor_state()`, read once per `run`; do not mutate it                                  |
| `read_editor_state()`       | `{ buf, win, mode, cursor, cfile, cword, selection, buffer_path }` read now, uncached         |

`selection` is the text of a **live** visual or select-mode selection (charwise, linewise or blockwise; read with
`getregion`, so the `'<`/`'>` marks of an earlier selection are never returned). A `:` command typed from visual
mode runs in normal mode: `selection` is `nil` there; `cfile`, `cword` and `buffer_path` are `nil` when empty.
