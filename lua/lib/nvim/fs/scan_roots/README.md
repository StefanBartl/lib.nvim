# `lib.nvim.fs.scan_roots`

Scan multiple root directories for files (or directories), with optional
directory-name ignoring and an optional TTL-based on-disk cache — the building
block behind "fast file index" features (fuzzy path pickers, truncated-path
search, project-wide scans).

Built on [`lib.nvim.fs.collect_recursive`](../collect_recursive/README.md) (the
actual walk) and [`lib.nvim.fs.json`](../json/README.md) (cache persistence);
neither is duplicated here.

Scanning is **sequential by design** — one root after another. Bounded-concurrency
async scanning was deliberately left out to keep the module simple; callers that
need it can invoke `scan` once per root from their own async scheduler.

## Usage

```lua
local scan_roots = require("lib.nvim.fs.scan_roots")

-- Plain scan
local files = scan_roots.scan({ "/repo/src", "/repo/lua" }, {
  ignore_dirs = { "node_modules", ".git" },
})

-- Cached scan: re-reads the cache for 60s, then rescans and rewrites it
local cached = scan_roots.scan({ "/repo" }, {
  ignore_dirs = { "node_modules", ".git", "target" },
  cache_path = vim.fn.stdpath("cache") .. "/my_plugin/scan.json",
  ttl_seconds = 60,
})

-- Directories instead of files
local dirs = scan_roots.scan({ "/repo" }, { kind = "dirs" })
```

## Options

| Field         | Type       | Default     | Meaning                                                       |
|---------------|------------|-------------|---------------------------------------------------------------|
| `ignore_dirs` | `string[]` | `{}`        | Directory names to skip (matched as a whole path component)   |
| `kind`        | `string`   | `"files"`   | `"files"`, `"dirs"` or `"all"` — forwarded to `collect_recursive` |
| `cache_path`  | `string?`  | `nil`       | When set, results are cached to this JSON file                |
| `ttl_seconds` | `integer?` | `nil`       | Cache lifetime; `nil` means the cache never expires            |

## Returns

A flat `string[]` of absolute paths, merged across all roots.
