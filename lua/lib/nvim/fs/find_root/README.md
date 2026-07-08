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

## Options — `Lib.Fs.FindRoot.Opts`

| Field      | Type        | Default     | Meaning                                            |
|------------|-------------|-------------|----------------------------------------------------|
| `markers`  | `string[]`  | `{ ".git" }`| Marker file/folder names that identify a root.     |
| `capacity` | `integer`   | `256`       | LRU capacity, keyed per directory.                 |
| `cache`    | `boolean`   | `true`      | Enable the per-directory LRU cache.                |

## Returns — `Lib.Fs.FindRoot`

| Field   | Type                             | Meaning                                          |
|---------|----------------------------------|--------------------------------------------------|
| `find`  | `fun(path: string): string?`     | Nearest ancestor dir containing a marker, or nil.|
| `clear` | `fun()`                          | Drop all cached lookups (e.g. after adding a marker).|

Negative results (no root found) are cached too, so repeated misses on the same
directory stay cheap.
