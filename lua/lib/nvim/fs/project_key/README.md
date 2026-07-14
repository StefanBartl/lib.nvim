# `lib.nvim.fs.project_key`

Stable per-project cache key.

Prefers the Git root of `path` (default: current working directory) via the
cached, marker-based [`find_root`](../find_root/README.md) (marker `.git`);
falls back to `path`/cwd itself when no `.git` ancestor is found. The result
is always run through [`normkey`](../normkey/README.md), so it is absolute,
canonical, and stable across casing/separator/symlink differences.

## Usage

```lua
local project_key = require("lib.nvim.fs.project_key")

project_key("/repo/src/a.lua")  --> "/repo"           (normkey'd Git root)
project_key()                    --> normkey'd cwd's Git root, or cwd itself
```

Uses `find_root`'s existing per-directory LRU cache — repeated calls for
files in the same directory are cheap. Use this wherever a plugin needs a
stable key to scope per-project state (persisted paths, session data, …).
