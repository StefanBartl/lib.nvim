# `lib.nvim.fs.mkdirp`

Recursive directory creation (`mkdir -p`) built **purely on libuv**.

## Why not `vim.fn.mkdir(path, "p")`

`vim.fn.*` must not be called from a *fast event context* — the callback of a
`uv` timer, an `fs_event` watcher, or a subprocess stdout/stderr reader. Doing
so aborts with:

```
E5560: Vimscript function must not be called in a fast event context
```

That makes `vim.fn.mkdir` unusable in exactly the place a log relay or a
download sink needs it: inside the callback that just received the data it
wants to write. Every call in this module is `vim.uv`/`vim.loop` only — no
`vim.fn`, no `vim.api`, no `vim.schedule`.

## Usage

```lua
local mkdirp = require("lib.nvim.fs.mkdirp")

local ok, err = mkdirp("/tmp/a/b/c")
if not ok then
  -- err is a human-readable message naming the offending component
end
```

Safe from a spawn callback:

```lua
local spawn_stream = require("lib.nvim.cross.uv.spawn_stream")

spawn_stream({ "my-server" }, nil, function(line)
  mkdirp(vim.fs.dirname(logfile))  -- no E5560
  -- … append `line`
end)
```

## Semantics

Matches `mkdir -p`:

| Case                                   | Result                                      |
|----------------------------------------|---------------------------------------------|
| Missing parents                        | Created                                     |
| Directory already exists               | `true` (not an error)                        |
| A component exists as a **file**       | `false, "mkdirp: not a directory: …"`        |
| Concurrent creator wins the race       | `true` (re-stat confirms it is a directory)  |
| Root only (`/`, `C:/`, `//srv/share`)  | `true` if it exists — roots are never created |

Directories are created with mode `0755`.

## Path handling

Backslashes are unified to `/` up front (libuv accepts `/` on Windows too), so
all of these work:

- POSIX absolute — `/tmp/a/b`
- Relative — `a/b` (resolved against the process cwd by libuv)
- Windows drive — `C:\a\b` / `C:/a/b` (the drive itself is never created)
- UNC — `//server/share/a` (neither server nor share is created)
- `.` components and trailing separators are skipped

## Returns

| Value | Type      | Meaning                                    |
|-------|-----------|--------------------------------------------|
| `ok`  | `boolean` | Directory exists after the call.            |
| `err` | `string?` | Message naming the failing component, or nil. |

## See also

- [`lib.nvim.fs.create_entry`](../create_entry/README.md) — creates a file or
  directory below a parent, and uses this module for its `mkdir -p` step. Note
  that `create_entry` itself is **not** fast-event safe: it still uses
  `vim.fn.resolve`/`filereadable`/`fnamemodify` for path handling. Call
  `mkdirp` directly from a fast event context.
