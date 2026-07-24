# `lib.nvim.fs.scan_cached`

Recursively scan one root directory, memoized **in-memory** with a TTL — the
session-lifetime counterpart to
[`lib.nvim.fs.scan_roots`](../scan_roots/README.md) (which persists to disk
across restarts). Built for repeated audit/report-style scans of the same
root within a single Neovim session — e.g. re-running a report with a
different filter — where a few seconds of staleness is fine and a fresh walk
on every call is not.

Built on [`lib.nvim.fs.collect_recursive`](../collect_recursive/README.md)
(the actual walk) and [`lib.nvim.cache.memory`](../../cache/README.md) (the
TTL cache); neither is duplicated here.

## Usage

```lua
local scan_cached = require("lib.nvim.fs.scan_cached")

local files = scan_cached.scan("/repo/lua", { ttl_seconds = 5 })

-- within 5s, a repeat call reuses the cached list instead of rescanning:
local same = scan_cached.scan("/repo/lua", { ttl_seconds = 5 })

-- force a rescan on demand:
local fresh = scan_cached.scan("/repo/lua", { ttl_seconds = 5, refresh = true })

-- only .lua files, skipping vendored trees:
local lua_files = scan_cached.scan("/repo/lua", {
  ignore = function(abs_path, is_dir)
    return not is_dir and abs_path:sub(-4) ~= ".lua"
  end,
})
```

## Options

| Field         | Type       | Default   | Meaning                                                  |
| ------------- | ---------- | --------- | --------------------------------------------------------- |
| `kind`        | `string`   | `"files"` | `"files"`, `"dirs"` or `"all"` — forwarded to `collect_recursive` |
| `ignore`      | `function` | –         | `(abs_path, is_dir) -> boolean`, forwarded to `collect_recursive` |
| `ttl_seconds` | `integer`  | `5`       | Cache freshness window                                    |
| `refresh`     | `boolean`  | `false`   | Force a rescan, bypassing (and refreshing) the cache       |

## Returns

A flat `string[]` of absolute paths under `root`.

## Notes

* The cache key is `root .. ":" .. kind` — scanning the same root for
  `"files"` and `"dirs"` separately caches independently.
* This module only caches the **walk**. If your call site does further
  work per path (parsing, stat-ing, …) that is itself expensive, cache that
  result separately — `scan_cached` does not know about it.
