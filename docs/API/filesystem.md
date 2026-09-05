# API Reference — `lib.nvim.fs.*` (filesystem / path helpers)

Part of the [lib.nvim API reference](README.md). 28 submodules covering
path resolution, root/project detection, directory creation and scanning,
file reading/writing, ignore lists, and opening files/URLs. All built on
`vim.fs`/`vim.uv` (or `vim.loop` fallback), not shell commands, unless noted.

---

## Working-directory management

### `lib.nvim.fs.chdir` (see README)
Scope-aware working-directory change (global `:cd` / tab `:tcd` / window
`:lcd`), with path normalization via `normkey`, validation, and no throwing.

```
return function(path: string, opts?: Lib.Fs.Chdir.Opts): boolean ok, string? err
```
`opts.scope: "global"|"tab"|"win"` (default `"global"`), `opts.win`, `opts.tab`.

### `lib.nvim.fs.dir_guard` (see README)
Holds the working directory on a path until released, undoing foreign
`DirChanged` events; built on `chdir`.

```
M.hold(path: string, opts?: Lib.Fs.DirGuard.Opts): Lib.Fs.DirGuard.Handle? handle, string? err
```
`opts`: `scope`, `win`/`tab`, `on_violation: fun(new_cwd, held): boolean?`, `on_error: fun(err)`.

Returned handle (closure-based, dot syntax, no `self`):
```
handle.path(): string
handle.is_held(): boolean
handle.update(new_path: string): boolean ok, string? err
handle.bypass(fn: fun()): ...     -- runs fn unguarded, then restores; returns pcall result
handle.release(): nil
```

---

## Root / project detection

### `lib.nvim.fs.find_upward_dir` (see README)
Uncached primitive: walk upward from a directory and return the nearest
ancestor holding one of a set of marker names (plain names or `*`/`?`
globs). Underneath `find_root`.

```
return function(names: string[], from: string, opts?: { stop?: string }): string|nil
```
Sibling `lib.nvim.fs.find_upward_dir.matcher` (no README) — glob-aware
marker matching shared with `find_root`:
```
M.has_glob(names: string[]): boolean
M.build(names: string[]): fun(name: string, path?: string): boolean
```

### `lib.nvim.fs.find_root` (see README)
Cached, marker-based project-root finder (factory). LRU-cached per
directory (or per full chain with `cache_chain`), with `skip_dirs`/
`max_depth` bounding. Built on `find_upward_dir` + `lib.lua.memo.lru`.

```
return function(opts?: Lib.Fs.FindRoot.Opts): Lib.Fs.FindRoot
```
`opts`: `markers: string[]` (default `{".git"}`), `capacity`, `cache`,
`cache_chain`, `skip_dirs`, `max_depth`.
```
finder.find(path: string): string|nil
finder.clear(): nil
```

### `lib.nvim.fs.project_key` (see README)
Stable per-project cache key: prefers the Git root of `path` (via
`find_root`, marker `.git`), falls back to `path`/cwd, always run through
`normkey`.

```
return function(path?: string): string
```

### `lib.nvim.fs.polymorphic_rootresolver` (see README)
Polymorphic LSP root-directory resolver: accepts a filename or bufnr, finds
VCS/config markers upward via `vim.fs.root`, optional `stdpath("config")`
fallback, optional callback.

```
return function(cfg?: RootResolverCfg): fun(arg: string|integer, cb?: fun(root: string)): string
```
`cfg.markers` (default `{".git",".hg",".svn"}`), `cfg.include_stdpath_config` (default `true`).
See also its sibling `example-setup-luals-marksman.md` setup guide.

---

## Path resolution / string manipulation

### `lib.nvim.fs.normkey` (see README)
Canonical, cross-platform cache/dedup key for a path: expands `~`,
optionally resolves symlinks (`uv.fs_realpath`, on by default), forces
forward slashes, uppercases the Windows drive letter, collapses duplicate
separators (UNC-safe).

```
return function(p: string, opts?: { realpath?: boolean }): string   -- realpath default true
```

### `lib.nvim.fs.relpath` (no README)
Compute `path` relative to `base` (both made absolute + forward-slash
normalized); `..`-climbs POSIX-style from the common ancestor; returns the
absolute path unchanged if the two paths share no root (e.g. different
Windows drives).

```
return function(path: string, base: string): string
```

### `lib.nvim.fs.path_shorten` (see README)
Shorten a path for display: `"fit"` (default; ellipsis-collapses the
middle to fit `max_len`) or `"label"` (Harpoon-style
`<root>/<ellipsis>/<parent>/<file>`, ignores `max_len`).

```
return function(path: string, max_len: integer|nil, opts?: Lib.Fs.PathShortenOpts): string
```
`opts.style: "fit"|"label"` (default `"fit"`), `opts.ellipsis`.

### `lib.nvim.fs.path` (see README)
Small grab-bag of path helpers.

```
M.from_repo_relative(raw: string): string   -- resolves repo-root-relative (or absolute) path
M.joinpath(parts: string[]): string          -- wraps vim.fs.joinpath, table.concat fallback
M.ensure_dir(path: string): boolean ok, string? err   -- ensures the *parent* dir of a file exists (fast-event safe)
```

### `lib.nvim.fs.is_subpath` (see README)
```
return function(path: string, base: string): boolean   -- equality included
```

### `lib.nvim.fs.is_valid_filename` (see README)
Validates a bare filename (not a full path) for cross-platform filesystem
safety — rejects Windows-illegal characters `\/:*?"<>|`, embedded NUL,
nil/non-string/empty/whitespace-only.

```
return function(name: string|nil): boolean ok, string|nil err
```

---

## Stat checks

### `lib.nvim.fs.is_dir` (see README)
```
return function(p: string): boolean   -- false on any missing path or stat failure, never raises
```

### `lib.nvim.fs.is_readable_file` (see README)
Despite the name, true for a readable file **or** an existing directory.

```
return function(filepath: string): boolean
```

---

## Directory creation

### `lib.nvim.fs.mkdirp` (see README)
Recursive directory creation (`mkdir -p`) built purely on libuv
(`vim.uv`/`vim.loop` only, no `vim.fn`) — safe from fast-event contexts (uv
timers, `fs_event`, spawn callbacks; `vim.fn.mkdir` there aborts with
`E5560`). Handles POSIX/relative/Windows-drive/UNC paths; mode `0755`.

```
return function(path: string): boolean ok, string|nil err
```

### `lib.nvim.fs.create_entry` (see README)
Create a file or directory relative to a parent directory — shared core
for "create file/folder" picker actions. Trailing separator on `name` →
directory (`mkdir -p` via `mkdirp`); otherwise creates an empty file
(parents via `mkdirp`). Validates each path segment via `is_valid_filename`.

```
return function(parent_dir: string, name: string): boolean ok, "file"|"directory"|nil kind, string|nil path_or_err
```

---

## Directory scanning / walking

### `lib.nvim.fs.collect_recursive` (see README)
Recursive directory walker on `fs_scandir`/`fs_scandir_next`.

```
M.collect(root: string, opts?: Lib.Fs.CollectRecursive.Opts): string[]
  -- opts.kind: "all"|"files"|"dirs" (default "all"), opts.ignore: fun(abs_path, is_dir): boolean
M.files(root: string, opts?): string[]   -- shorthand, kind = "files"
M.dirs(root: string, opts?): string[]    -- shorthand, kind = "dirs"
M.collect_async(root: string, opts?: Lib.Fs.CollectRecursive.Opts, on_done: fun(paths: string[])): fun() cancel
  -- non-blocking counterpart; coroutine-driven over async fs_scandir/fs_stat, one dir
  -- at a time (not parallel); on_done always vim.schedule-dispatched, never after cancel()
M.files_async(root: string, opts?, on_done): fun() cancel   -- shorthand, kind = "files"
M.dirs_async(root: string, opts?, on_done): fun() cancel    -- shorthand, kind = "dirs"
```

### `lib.nvim.fs.scan_cached` (see README)
Recursively scan one root, memoized in-memory with a TTL (session
lifetime); built on `collect_recursive` + `lib.nvim.cache.memory`.

```
M.scan(root: string, opts?: Lib.Fs.ScanCached.Opts): string[]
M.scan_async(root: string, opts?: Lib.Fs.ScanCached.Opts, on_done: fun(paths: string[])): nil
  -- non-blocking counterpart; a miss walks via collect_recursive.collect_async,
  -- a hit still calls on_done (vim.schedule-dispatched either way)
```
`opts`: `kind` (default `"files"`), `ignore`, `ttl_seconds` (default 5), `refresh`.

### `lib.nvim.fs.scan_roots` (see README)
Scan multiple root directories, with directory-name ignoring and an
optional TTL-based on-disk JSON cache. Sequential by design — `scan_async`
too, one root at a time, not in parallel.

```
M.scan(roots: string[], opts?: Lib.Fs.ScanRoots.Opts): string[]
M.scan_async(roots: string[], opts?: Lib.Fs.ScanRoots.Opts, on_done: fun(paths: string[])): nil
  -- non-blocking counterpart; the JSON cache file itself is still read/written
  -- synchronously, only the per-root walk is async
```
`opts`: `ignore_dirs` (default `{}`), `kind` (default `"files"`), `cache_path?`, `ttl_seconds?` (nil = never expires).

---

## Ignore lists

### `lib.nvim.fs.ignore.list` (see README)
Centralized, canonical filesystem ignore rules (basenames + Lua patterns)
for developer tooling doing recursive traversal. No filesystem IO;
heuristic/conservative, not a `.gitignore` replacement.

```
M.basenames: string[]                        -- e.g. .git, node_modules, dist, .venv, ...
M.patterns: string[]                          -- Lua patterns, e.g. %.log, pnpm%-lock.yaml
M.normalize(s: string): string                -- trims trailing slash, lowercases on Windows
M.as_set(): table<string, boolean>            -- basenames as a lookup set
M.as_luals_patterns(): string[]               -- basenames -> LuaLS workspace.ignoreDir globs
M.as_telescope_patterns(): string[]           -- basenames + patterns, for file_ignore_patterns
M.as_neotree_names(): string[]                -- basenames only, for Neo-tree hide_by_name
```

---

## File reading / writing / mutation

### `lib.nvim.fs.read` (see README)
```
return function(path: string): string|nil content, string|nil err   -- binary mode, byte-exact
```

### `lib.nvim.fs.write.to_file` (see README)
Synchronous, byte-exact write (creates parent dir, truncates, binary
`"wb"`, appends trailing newline if missing).

```
return function(path: string, content: string): boolean, string|nil
```

### `lib.nvim.fs.write.append` (see README)
Sibling of `write.to_file` (which truncates) — appends instead.

```
return function(path: string, content: string): boolean ok, string|nil err
```

### `lib.nvim.fs.write.async` (see README)
Asynchronous counterpart: creates parent dir synchronously, then writes via
libuv without blocking.

```
return function(path: string, content: string, cb: fun(ok: boolean, err: string|nil))
```

### `lib.nvim.fs.write.batch` (see README)
Write many files asynchronously via `write.async`, one callback once all
have settled.

```
return function(entries: {path: string, content: string}[], cb: fun(all_ok: boolean, results: {path, ok, err}[]))
```

### `lib.nvim.fs.json` (see README)
Read/write JSON files. Encoding via `lib.lua.json.encode`; decoding via
`vim.json.decode`. Writes are atomic (write to sibling `.tmp`, then
`fs_rename`).

```
M.read(path: string): table|nil decoded, string|nil err
M.write(path: string, tbl: table): boolean ok, string|nil err
```

### `lib.nvim.fs.trash` (see README)
Cross-platform "send to trash/recycle bin" (not permanent delete).
Dispatches to the OS-native mechanism (PowerShell on Windows, Finder via
`osascript` on macOS, `gio trash`/`trash-put` on Linux/WSL, XDG-move
fallback otherwise).

```
M.trash(path: string, cb: fun(ok: boolean, err: string|nil))   -- async
M.trash_blocking(path: string): boolean ok, string|nil err
```

---

## Opening files / URLs

### `lib.nvim.fs.open.url.system_opener` (see README) — **deprecated**
Use [`lib.nvim.cross.open_default`](cross-platform.md) instead. This module is
now a thin shim over it: `.open(url)` → `open_default(url)`, `.open(url, {
on_exit = f })` → `open_default(url, { on_exit = f })`. The old `cfg` fields
(`prefer_ui_open`, `enable_windows_opener`, `open_cmd_*`) and the
`vim.ui.open`-first dispatch are gone — no caller used them, and `open_default`
adds `expand_path` + WSL `wslpath` translation that this module lacked.

```
M.open(url: string, cfg?: table): boolean opened   -- shim: forwards only cfg.on_exit
M.is_like(s: string): boolean                        -- heuristic: http(s)://, file://, www., or bare name.tld (no replacement yet)
M.is_ike                                              -- deprecated misspelled alias of is_like
```
