# `lib.nvim.fs.json`

Read/write JSON files, built on `lib.nvim.json` for the actual
encode/decode (see that module if you need to decode a JSON string that
isn't coming from a file — an HTTP response body, say). Writes are atomic:
content is written to a sibling temp file unique per write (`*.tmp`), then renamed over the
destination.

## Usage

```lua
local json = require("lib.nvim.fs.json")

local ok, err = json.write("/tmp/state.json", { count = 1, tags = { "a", "b" } })

local tbl, err2 = json.read("/tmp/state.json")
-- tbl = { count = 1, tags = { "a", "b" } }
```

## Returns

| Function            | Returns                 | Meaning                                            |
|----------------------|--------------------------|------------------------------------------------------|
| `M.read(path)`        | `table\|nil, string\|nil` | Decoded table, or `nil` + error (`"read failed: ..."` or `"invalid JSON: ..."`) |
| `M.write(path, tbl)`  | `boolean, string\|nil`   | `true` on success, or `false` + error message         |
| `M.tmp_path(path)`    | `string`                 | A fresh temp path next to `path`, as `M.write` uses   |

## Atomicity

`M.write` encodes `tbl`, writes it to a sibling temp file unique to this write
(`M.tmp_path(path)`: `state.json` -> `state.<pid>-<n>-<hrtime>.json.tmp`, so two
Neovim instances writing the same file never share one temp file, and a sweeper
matching `*.json.tmp` still finds a write a crash left behind), then renames the
temp file over `path` via `fs_rename`. This is atomic on POSIX filesystems; on
Windows `fs_rename` is best-effort (it can fail if `path` is open elsewhere).
On rename failure, the `.tmp` file is cleaned up and `M.write` returns
`false, err`. If `path` is a symlink, the link target is written through (resolved with
`fs_realpath`) and the link stays a link; a dangling link is replaced like any other entry.
