# `lib.nvim.fs.read_bounded`

Read a file only when it is a **regular file** of at most `max_bytes` bytes.
The type and size are judged on the stat before the file is opened and again on
the open descriptor, and the read itself never takes more than `max_bytes + 1`
bytes (in blocks, so only what is there is allocated): a file that grows or is
swapped in between cannot exhaust memory. Meant for files inside a repository
somebody else controls -- a FIFO would block the read forever (the open is
non-blocking), a device never ends, a huge file exhausts memory. The bytes come
back exactly as stored (no `\r\n` rewriting).

## Usage

```lua
local read_bounded = require("lib.nvim.fs.read_bounded")

local content, err = read_bounded(dir .. "/.git/config", 256 * 1024)
if not content then
  return nil -- missing, not a regular file, or too large: `err` says which
end
```

## Returns

| # | Type      | Meaning                                              |
|---|-----------|------------------------------------------------------|
| 1 | `string?` | File content on success, `nil` on failure            |
| 2 | `string?` | `nil` on success, error message on failure           |

Errors: `invalid arguments` (not a string path, or a limit that is not a finite
number >= 0), `not found: ...`, `not a regular file: ...`,
`not a regular file within the limit: ...` (it changed after the stat),
`too large (N > M bytes): ...` / `too large (> M bytes): ...`, `open failed: ...`,
`read failed: ...`. It never raises.
A symlink to a regular file is followed by default (the stat is of the target);
pass `{ follow_symlinks = false }` as a third argument to refuse it
(`not a regular file`). A path swapped for a link between the check and the
open is refused as well: the opened file must be the one the `lstat` saw (same
inode and device).
