# `lib.nvim.store.project`

Persistent state keyed by **project**, so reopening the same project — even
on a different machine, via synced dotfiles/config — finds the same state
again. This is what [`lib.nvim.cache.disk`](../../cache/README.md) does not
provide: it persists JSON by a caller-chosen `namespace`, with no notion of
"which project is this for".

Combines two existing primitives, adding nothing but the root-resolution
step between them:

- [`lib.nvim.fs.project_key`](../../fs/project_key/README.md) — git root of
  the given/current path (falls back to the path itself when not in a
  work-tree), normalized. Used instead of calling `lib.nvim.git.repo_root`
  directly: it already implements "git root, else the given path" with a
  cached, marker-based lookup (no `git` subprocess per call).
- [`lib.nvim.cache.disk`](../../cache/README.md) — namespaced JSON
  persistence with TTL, `pcall`-guarded read/write.

## Usage

```lua
local store = require("lib.nvim.store.project")

store.save("cascade/anchors", { version = 1, files = { ... } })

local data = store.load("cascade/anchors")
-- data is nil if missing, unreadable, or (with ttl_seconds) expired

store.clear("cascade/anchors")

store.root()   -- the resolved, normalized project root backing the above
store.stats("cascade/anchors")
```

## Options

| Field         | Type     | Default                                            | Meaning                                                   |
| ------------- | -------- | --------------------------------------------------- | ----------------------------------------------------------- |
| `path`        | `string` | cwd                                                 | Path to resolve the project root from — affects **which** project's storage is used, not what's stored |
| `dir`         | `string` | `stdpath("cache") .. "/lib.nvim/store/project"`     | Parent storage directory; each project gets one subdirectory under it |
| `ttl_seconds` | `integer`| –                                                   | `load` only: treat entries older than this as expired      |

## Returns

- `save(key, data, opts?)` → `boolean ok, string|nil err`
- `load(key, opts?)` → `any|nil` (`nil` if missing/unreadable/expired)
- `clear(key, opts?)` → `boolean ok`
- `root(opts?)` → `string`
- `stats(key, opts?)` → `{ exists, saved_at, age_seconds, size_bytes }`

## Notes

- The project's storage directory is a short hash of its normalized root
  path, not the path itself — keeps the on-disk tree flat regardless of
  where projects live, and avoids leaking directory structure into
  `stdpath("cache")`.
- Non-git projects still work: `project_key` falls back to the given/current
  path itself, so storage is stable across restarts as long as you open
  from the same directory. It's just not portable across machines the way a
  git-rooted key synced via dotfiles is.
- `key` follows the same convention as `lib.nvim.cache.disk`'s `namespace` —
  a flat string is safest; a key containing `/` maps to a nested path that
  this module (like `cache.disk`) does not create parent directories for.

## Migration candidates

Several plugins hand-roll project-keyed JSON persistence today (window/buffer
layout, tree scroll state, spell-ignore lists, command favorites, API
metrics, filesystem-scan caches, picker history — see
[project-store.md](../../../../../docs/ROADMAP/project-store.md) for the full
list). None need to change; this is a "when convenient" simplification, not
a required migration.
