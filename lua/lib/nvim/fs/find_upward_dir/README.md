# `lib.nvim.fs.find_upward_dir`

Walk upward from a starting directory and return the nearest ancestor holding
one of a set of marker names.

Markers may be plain basenames (`.git`, `package.json`) or shell-style globs
(`*.rockspec`, using `*`/`?`). `vim.fs.find`'s name-list form compares names
verbatim and can't express a glob, so a marker set containing one is compiled
into `vim.fs.find`'s predicate form instead (see `matcher.lua`); a plain
marker set keeps taking the cheaper list-form path unchanged.

This is the uncached primitive underneath
[`lib.nvim.fs.find_root`](../find_root/README.md), which adds LRU caching,
`skip_dirs`/`max_depth` bounding, and chain-caching on top. Reach for
`find_root` unless you specifically need an uncached, one-off upward search.

## Usage

```lua
local find_upward_dir = require("lib.nvim.fs.find_upward_dir")

find_upward_dir({ ".git" }, "/repo/src")                 --> "/repo"
find_upward_dir({ "*.rockspec" }, "/repo/src")            --> nearest ancestor with a *.rockspec file, or nil
find_upward_dir({ ".git" }, "/repo/src", { stop = "/" })  --> gives up at "/" (exclusive; "/" itself isn't searched)
```

Returns `nil` when no ancestor matches before `opts.stop` (or the filesystem
root) is reached.
