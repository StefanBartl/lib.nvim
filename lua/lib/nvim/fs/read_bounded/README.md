# `lib.nvim.fs.read_bounded`

`lib.nvim.fs.read` with a guard: the file is read only when it is a **regular
file** of at most `max_bytes` bytes, judged on the stat before it is opened.
Meant for files inside a repository somebody else controls — a FIFO would block
the read forever, a device never ends, a huge file exhausts memory.

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

Errors: `not found: …`, `not a regular file: …`, `too large (N > M bytes): …`,
or whatever `lib.nvim.fs.read` reports (`open failed: …`).
A symlink to a regular file is followed (the stat is of the target).
