# Filesystem

`lib.nvim.fs.*` — the single largest namespace in the library (28
submodules): working-directory management, root/project detection, path
resolution, stat checks, directory creation/scanning (sync and async),
ignore lists, file read/write/mutation, and opening files/URLs. Built on
`vim.fs`/`vim.uv` (or the `vim.loop` fallback), not shell commands, unless
explicitly noted.

## Scope-aware working-directory change

A `:cd`/`:tcd`/`:lcd` wrapper that normalizes and validates the path first
and never throws — a plugin can request a directory change without knowing
which scope its caller wants.

- **Module:** `lib.nvim.fs.chdir`
- **Config:** `opts.scope` — `"global"` (default) | `"tab"` | `"win"`

## Held working directory (`dir_guard`)

Pins the working directory to a path until released, actively undoing any
foreign `DirChanged` event that tries to move it away in the meantime — for
an operation (a build, a long-running scan) that must not have its cwd
yanked out from under it by an unrelated autocmd.

- **Module:** `lib.nvim.fs.dir_guard` (`hold`)

```lua
local handle = require("lib.nvim.fs.dir_guard").hold("/repo")
handle.bypass(function() vim.cmd("cd /elsewhere") end)  -- runs unguarded, then restores
handle.release()
```

## Project-root detection

A cached, marker-based upward search for the nearest ancestor directory
holding a marker file/glob (`.git` by default) — the shared primitive behind
LSP root resolution, `:cd`-to-project commands, and per-project cache keys.

- **Module:** `lib.nvim.fs.find_root` (factory), `lib.nvim.fs.find_upward_dir`
  (uncached primitive underneath it)
- **Config:** `opts.markers` (default `{".git"}`), `capacity`, `cache_chain`,
  `skip_dirs`, `max_depth`

```lua
local finder = require("lib.nvim.fs.find_root")({ markers = { ".git", "Cargo.toml" } })
local root = finder.find(vim.fn.expand("%:p"))
```

## Stable per-project cache key

Derives one canonical string per project — prefers the Git root, falls back
to the raw path/cwd, always normalized — so two plugins caching data "per
project" land on the same key without coordinating.

- **Module:** `lib.nvim.fs.project_key`

## Polymorphic LSP root resolver

A root-directory resolver shaped for LSP `root_dir` configs: accepts either
a filename or a bufnr, walks upward through VCS/config markers via
`vim.fs.root`, with an optional `stdpath("config")` fallback.

- **Module:** `lib.nvim.fs.polymorphic_rootresolver`
- **Config:** `cfg.markers` (default `{".git",".hg",".svn"}`),
  `cfg.include_stdpath_config` (default `true`)

## Canonical path key (`normkey`)

Turns any path spelling into one canonical, cross-platform cache/dedup key —
expands `~`, resolves symlinks by default, forces forward slashes,
uppercases the Windows drive letter, and collapses duplicate separators
(UNC-safe). Two different-looking paths to the same file always normalize to
the same key.

- **Module:** `lib.nvim.fs.normkey`

## Display-friendly path shortening

Two shortening styles for a path that's too long to show in a statusline or
picker row: middle-ellipsis to fit a max length, or a Harpoon-style
`<root>/…/<parent>/<file>` label.

- **Module:** `lib.nvim.fs.path_shorten`
- **Config:** `opts.style` — `"fit"` (default) | `"label"`

## Recursive directory walking — sync and async

The recursive scanner underneath every other scan/cache module in this
namespace, plus two layers built on it: TTL-memoized single-root scans, and
multi-root scans with directory-name ignoring.

- **Tab:** true
- **Module:** `lib.nvim.fs.collect_recursive` (`collect`/`files`/`dirs` and
  their `_async` counterparts), `lib.nvim.fs.scan_cached` (`scan`/`scan_async`),
  `lib.nvim.fs.scan_roots` (`scan`/`scan_async`)
- **Deep dive:** [`docs/guides/async-directory-walk.md`](../guides/async-directory-walk.md)

Recursive directory scans block the main loop on a large tree —
`fs_scandir`/`fs_stat` called without a callback wait for the syscall
synchronously, which is fine for a handful of directories but stalls
Neovim's entire input/redraw loop for the duration of a `node_modules` or a
monorepo scan.

libuv's own callback-form `fs_scandir`/`fs_stat` are genuinely async, but
threading raw callbacks through recursive directory descent produces the
same callback-pyramid mess async filesystem work always risks. The fix is a
minimal coroutine-based async/await private to `collect_recursive`:
`await(starter)` suspends the running coroutine until a libuv callback
fires; `walk_async` reads like a plain recursive function — one `await()`
per libuv call — while every `await()` actually yields control back to the
event loop.

```lua
local collect_recursive = require("lib.nvim.fs.collect_recursive")
local cancel = collect_recursive.collect_async("/repo", { kind = "files" }, function(paths)
  -- vim.schedule-dispatched, never called for a cancelled walk
end)
-- cancel()  -- stop early, e.g. when the requesting picker closes
```

`scan_cached.scan_async` and `scan_roots.scan_async` build directly on this:
a cache hit still calls `on_done` (so both branches look the same to a
caller), a miss walks via `collect_async`. Deliberately **not** a wall-clock
speedup — this walks one directory at a time, never in parallel, so it can
be slower in wall time than the synchronous walk on a tree that would have
finished fast anyway; the fix targets UI responsiveness, not raw scan
throughput. `scan_roots` visits multiple roots sequentially by design, sync
or async. `collect_async` returns a `cancel()` that stops the walk after the
current in-flight libuv call settles and skips `on_done` entirely — not "a
partial result," genuinely never called.

See [async-directory-walk.md](../guides/async-directory-walk.md) for the full
problem/solution write-up, including verified equivalence against the
synchronous walkers.

## Centralized ignore rules

One canonical set of basenames (`.git`, `node_modules`, `dist`, `.venv`, …)
and Lua patterns (`%.log`, `pnpm%-lock.yaml`, …) for developer-tooling
traversal, exported in the shape five different consumers need — a raw
lookup set, LuaLS `workspace.ignoreDir` globs, Telescope
`file_ignore_patterns`, and Neo-tree `hide_by_name` names — so a plugin
never re-derives its own ignore list from scratch.

- **Module:** `lib.nvim.fs.ignore.list` (`basenames`, `patterns`, `as_set`,
  `as_luals_patterns`, `as_telescope_patterns`, `as_neotree_names`)

## Byte-exact file read/write/mutation

Binary-mode read and write (not `vim.fn.readfile`/`writefile`'s
line-splitting) plus async and batch variants and atomic JSON read/write.

- **Module:** `lib.nvim.fs.read`, `lib.nvim.fs.write.to_file` (truncates),
  `lib.nvim.fs.write.append`, `lib.nvim.fs.write.async`,
  `lib.nvim.fs.write.batch`, `lib.nvim.fs.json` (`read`/`write`)

`write.to_file` creates the parent directory, truncates, writes binary, and
appends a trailing newline if missing. `fs.json.write` is atomic (writes to
a sibling `.tmp` file, then `fs_rename`), so a crash mid-write never leaves
a half-written JSON file where a caller expects a complete one.

## Cross-platform trash (not permanent delete)

Sends a path to the OS trash/recycle bin instead of unlinking it outright —
dispatches to the OS-native mechanism (PowerShell on Windows, Finder via
`osascript` on macOS, `gio trash`/`trash-put` on Linux/WSL, with an XDG-move
fallback).

- **Module:** `lib.nvim.fs.trash` (`trash`, `trash_blocking`)

## File/directory creation with validation

Shared core for "create file" / "create folder" picker actions — trailing
separator on the name makes a directory (`mkdir -p`), otherwise an empty
file (parents auto-created), with every path segment checked against
cross-platform filename rules before anything touches disk.

- **Module:** `lib.nvim.fs.create_entry`, `lib.nvim.fs.mkdirp`,
  `lib.nvim.fs.is_valid_filename`

`mkdirp` is built purely on `vim.uv`/`vim.loop` (no `vim.fn`), which makes
it safe to call from a fast-event context (a uv timer, an `fs_event`
callback, a spawn callback) where `vim.fn.mkdir` would abort with `E5560`.

## Opening files and URLs with the OS default handler

Two independent implementations of the same underlying problem, kept
because one predates the other: `fs.open.url.system_opener` (`vim.ui.open`
first, then a per-OS argv list) and the newer, more complete
`lib.nvim.cross.open_default` (adds WSL `wslpath` translation). Prefer
`cross.open_default` for new code.

- **Module:** `lib.nvim.fs.open.url.system_opener`,
  `lib.nvim.cross.open_default`
