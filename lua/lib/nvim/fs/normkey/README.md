# `lib.nvim.fs.normkey`

Canonical, cross-platform cache/dedup key for a filesystem path.

Expands `~`, optionally resolves symlinks via `uv.fs_realpath` (on by
default), forces forward slashes, uppercases a Windows drive letter, and
collapses duplicate separators — with an explicit UNC guard so a
`//server/share/...` prefix is never collapsed to a single slash.

`fs_realpath` only works on a path that exists. When it fails, this module
resolves the **nearest existing ancestor** and re-appends the unresolved tail,
so a path keys the same before and after it is created. That is not a nicety:
on Windows `$TEMP` is the 8.3 short form (`C:/Users/STEFAN~1/...`) for any
profile name longer than eight characters, so returning the input verbatim
gave one key before `mkdir` and a different one after — and a key that changes
when the directory appears is not a key. Anything cached under it beforehand
could never be found again.

Built from `lib.nvim.cross.fs.separators.{unify_slashes,drive_upper}`.
Deliberately does **not** route through
[`collapse_dots`](../../cross/fs/separators/README.md) for the repeated-slash
step: that module has a confirmed gap where it doesn't special-case a UNC
prefix and would corrupt one (`//server/share` → `/server/share`). This
module keeps its own guarded collapse instead.

## Usage

```lua
local normkey = require("lib.nvim.fs.normkey")

normkey("c:/repos//lib.nvim/../lib.nvim")  --> realpath-resolved, e.g. "C:/repos/lib.nvim"
normkey("~/notes.md")                       --> "/home/you/notes.md"
normkey([[\\SERVER\Share\proj]], { realpath = false })
                                             --> "//SERVER/Share/proj" (UNC preserved)
normkey(path, { realpath = false })         --> skip symlink resolution
```

## Options — `Lib.Fs.NormkeyOpts`

| Field      | Type      | Default | Meaning                                    |
|------------|-----------|---------|---------------------------------------------|
| `realpath` | `boolean` | `true`  | Resolve symlinks via `uv.fs_realpath`, falling back to the nearest existing ancestor. |

`realpath = false` skips the filesystem entirely: the answer comes from the
spelling alone, which is what you want when the path may not exist and you do
not care, or when you must not pay a syscall.

Two paths that refer to the same file (different casing, mixed separators, a
symlink) normalize to the same key — use this wherever paths are compared or
deduplicated (e.g. `lib.nvim.fs.project_key`).
