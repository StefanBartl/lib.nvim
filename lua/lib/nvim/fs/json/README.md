# `lib.nvim.fs.json`

Read/write JSON files. Encoding is built on `lib.lua.json.encode`; decoding
uses Neovim's built-in `vim.json.decode` (`lib.lua.json` only exposes an
encoder and array-shape decode *helpers*, not a general JSON-string parser).
Writes are atomic: content is written to a sibling `.tmp` file, then renamed
over the destination.

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

## Atomicity

`M.write` encodes `tbl`, writes it to `path .. ".tmp"`, then renames the temp
file over `path` via `fs_rename`. This is atomic on POSIX filesystems; on
Windows `fs_rename` is best-effort (it can fail if `path` is open elsewhere).
On rename failure, the `.tmp` file is cleaned up and `M.write` returns
`false, err`.
