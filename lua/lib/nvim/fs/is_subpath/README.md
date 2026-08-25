The function checks whether `path` lies within `base` (equality included). Step by step:

1. Both paths are normalized via `vim.fs.normalize`, which always yields forward-slash paths — on every OS, including Windows.
2. If the normalized strings are exactly equal, `path` counts as a subpath (same directory → `true`).
3. If the length of `path` is shorter than or equal to the length of `base` (but not equal, since the check above would already have returned false), `path` cannot lie within `base` → `false`.
4. `/` is used as the separator (matching what `vim.fs.normalize` produces). If `base` does not end with `/`, one is appended — this ensures that only whole directory names count as a prefix (e.g. `/foo/bar` ≠ `/foo/b`, because `/foo/b` + `/` becomes `/foo/b/`).
5. Finally it checks whether the first `#base` characters of `path` equal `base`; if so, `path` lies within `base` → `true`, otherwise `false`.

> **Windows note:** an earlier version appended `package.config:sub(1,1)` (the
> native separator, `\` on Windows) instead of `/` in step 4. Since
> `vim.fs.normalize` always produces `/`, that appended `\` never matched —
> `is_subpath` returned `false` for every genuine subpath on Windows. Fixed to
> use `/` consistently.

## Optional canonicalization (`opts`)

Steps 1–5 above describe the default: a pure `vim.fs.normalize` string
comparison, no syscalls, cheap enough for a `BufReadPost`/`BufWritePost` hot
path. `vim.fs.normalize` is a *string* operation, though — it cannot see that
two differently spelled paths name the same directory:

```lua
-- vim.fn.tempname() on Windows: "C:/Users/STEFAN~1/AppData/Local/Temp/nvim.0/x/0"
is_subpath(vim.fn.tempname(), "C:/Users/Stefan/AppData/Local/Temp")
--> false, although the file really does live under that directory
```

An 8.3 short name on Windows, a symlinked prefix (`/var` → `/private/var` on
macOS) — only a `uv.fs_realpath` resolves those. Both sides of a comparison
agree on a spelling only when they came from the same source, and they
frequently do not: `vim.fn.tempname()`, an LSP `root_dir`, a `getcwd()`
inherited from another process and a hand-written config path all spell the
same directory differently.

Pass a third argument to route both sides through
[`lib.nvim.fs.normkey`](../normkey/README.md) instead of `vim.fs.normalize`:

```lua
is_subpath(path, base)                       -- normalize only (default, unchanged)
is_subpath(path, base, {})                   -- normkey both sides, realpath on
is_subpath(path, base, { realpath = true })  -- same, explicit
is_subpath(path, base, { realpath = false }) -- normkey without the fs_realpath syscall
```

`{ realpath = false }` still buys the drive-letter uppercasing and separator
collapsing without touching the filesystem — useful when the paths may not
exist yet. The default `true` adds one `uv.fs_realpath` stat per side, which
is what resolves symlinks and short names.

This is deliberately opt-in rather than the default. Making `normkey` the
default would fix every caller at once, but it would also add two stat calls
to every existing call site unasked — including the ones already normalizing
their arguments themselves before calling in.
