# `lib.nvim.fs.normkey`

Canonical, cross-platform cache/dedup key for a filesystem path.

Expands `~`, optionally resolves symlinks via `uv.fs_realpath` (on by
default), forces forward slashes, uppercases a Windows drive letter, and
collapses duplicate separators — with an explicit UNC guard so a
`//server/share/...` prefix is never collapsed to a single slash.

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
| `realpath` | `boolean` | `true`  | Resolve symlinks via `uv.fs_realpath`.       |

Two paths that refer to the same file (different casing, mixed separators, a
symlink) normalize to the same key — use this wherever paths are compared or
deduplicated (e.g. `lib.nvim.fs.project_key`).
