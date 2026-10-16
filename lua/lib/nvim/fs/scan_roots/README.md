# `lib.nvim.fs.scan_roots`

Scan multiple root directories for files (or directories), with optional
directory-name ignoring and an optional TTL-based on-disk cache — the building
block behind "fast file index" features (fuzzy path pickers, truncated-path
search, project-wide scans).

Built on [`lib.nvim.fs.collect_recursive`](../collect_recursive/README.md) (the
actual walk) and [`lib.nvim.fs.json`](../json/README.md) (cache persistence);
neither is duplicated here.

Scanning is **sequential by default** — one root after another, whether via
`scan` (blocking) or `scan_async` (non-blocking, below). `scan_async` can walk
several roots at once with `opts.concurrency` (a bounded work queue, built on
`lib.nvim.async.map_limit`); a single root is always walked directory by directory.

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

-- Non-blocking counterpart: same options, roots walked one at a time by default via
-- collect_recursive.collect_async instead of stalling the main loop.
scan_roots.scan_async({ "/repo" }, { ignore_dirs = { "node_modules" } }, function(files)
  -- ...
end)
```

## Options

| Field         | Type       | Default     | Meaning                                                       |
|---------------|------------|-------------|---------------------------------------------------------------|
| `ignore_dirs` | `string[]` | `{}`        | Directory names to skip (matched as a whole path component)   |
| `kind`        | `string`   | `"files"`   | `"files"`, `"dirs"` or `"all"` — forwarded to `collect_recursive` |
| `concurrency` | `integer?` | `1`         | `scan_async` only: how many roots are walked at once; the result keeps the order of `roots` |
| `cache_path`  | `string?`  | `nil`       | When set, results are cached to this JSON file                |
| `ttl_seconds` | `integer?` | `nil`       | Cache lifetime; `nil` means the cache never expires            |

The cache file records the `roots`, `kind` and `ignore_dirs` it was written
for. A read through the same `cache_path` with any of them different is a
miss (rescan, rewrite), not a hit — otherwise one shared file would hand a
`"dirs"` scan the previous `"files"` answer, and with `ttl_seconds` unset it
would do so forever.

## Returns

A flat `string[]` of absolute paths, merged across all roots, plus `errors`:
`collect_recursive`'s unreadable-directory reports merged across roots, or
`nil`. A scan that reported any error is returned as-is but **not written to
`cache_path`** — with `ttl_seconds` unset the cache never expires, so "this
root was unavailable once" must not become "this project has no files"
across restarts.

## `scan_async(roots, opts?, on_done)`

Non-blocking counterpart to `scan`. Same options and cache semantics — the
cache file itself is still read/written synchronously (one small JSON file,
not the part that scales badly); only the per-root walk becomes async.
Roots are walked one `collect_recursive.collect_async` at a time, unless
`opts.concurrency = n` lets up to `n` roots be in flight (default `1`). The result is merged
in the order of `roots` whichever walk finishes first, so it does not depend on timing. A
root that fails with an error is reported in `errors` and does not stop the others.
`on_done(paths, errors)` fires exactly once, always `vim.schedule`-dispatched — directly
on a cache hit, via `map_limit` otherwise.
