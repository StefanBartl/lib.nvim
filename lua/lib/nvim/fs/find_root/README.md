# `lib.nvim.fs.find_root`

Cached, marker-based project-root finder.

Given a file (or directory) path, it walks upward to the nearest ancestor that
contains any of the configured marker names (default `.git`) and returns that
ancestor directory. Results are cached **per directory** in an LRU cache — every
file in a directory shares the same root, so a session that opens many files
across a project computes each directory's root at most once.

Built on [`find_upward_dir`](../find_upward_dir/init.lua) +
[`lib.lua.memo.lru`](../../../lua/memo/lru.lua).

## Usage

```lua
local find_root = require("lib.nvim.fs.find_root")

-- Factory: build a finder (default markers { ".git" }, LRU capacity 256).
local finder = find_root({ markers = { ".git" } })

finder.find("/repo/src/a.lua")  --> "/repo"   (nearest ancestor holding .git)
finder.find("/tmp/loose.txt")   --> nil       (no marker found)
finder.clear()                  -- drop all cached lookups
```

## Glob markers

Markers are basenames, and may use `*` / `?` wildcards. That covers the
ecosystems whose root marker has no fixed name:

```lua
local finder = find_root({
  markers = { ".git", "package.json", "Cargo.toml", "*.rockspec", "*.cabal" },
})
```

Plain (glob-free) marker sets keep taking the cheaper `vim.fs.find` name-list
path; a set containing a glob is compiled into a predicate instead.

## Chain caching

By default only the *queried* directory is cached. With `cache_chain = true`
the upward walk is done in this module and **every directory passed on the
way** is cached with the resolved root:

```lua
local finder = find_root({ markers = { ".git" }, cache_chain = true })

finder.find("/repo/a/b/c/x.lua")  --> "/repo"  (walks and caches a, b, c, repo)
finder.find("/repo/a/y.lua")      --> "/repo"  (cache hit, no filesystem access)
```

Worth it when many files across one deep tree are resolved in a session; the
plain mode stays cheaper for scattered one-off lookups. Because a chain
inserts several entries per walk, the default LRU capacity rises to 512 in
this mode.

## Options — `Lib.Fs.FindRoot.Opts`

| Field         | Type        | Default        | Meaning                                                            |
|---------------|-------------|----------------|--------------------------------------------------------------------|
| `markers`     | `string[]`  | `{ ".git" }`   | Marker file/folder names identifying a root; `*`/`?` globs allowed. |
| `capacity`    | `integer`   | `256` / `512`  | LRU capacity, keyed per directory. `512` when `cache_chain` is set. |
| `cache`       | `boolean`   | `true`         | Enable the per-directory LRU cache.                                 |
| `cache_chain` | `boolean`   | `false`        | Cache every directory on the way up, not just the queried one.      |

## Returns — `Lib.Fs.FindRoot`

| Field   | Type                             | Meaning                                          |
|---------|----------------------------------|--------------------------------------------------|
| `find`  | `fun(path: string): string?`     | Nearest ancestor dir containing a marker, or nil.|
| `clear` | `fun()`                          | Drop all cached lookups (e.g. after adding a marker).|

Negative results (no root found) are cached too, so repeated misses on the same
directory stay cheap.
