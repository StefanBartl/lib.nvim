# `lib.nvim.cross.fs.separators`

Small, **pure** path-separator helpers. None of them touch the filesystem,
expand `~`/env vars, or resolve symlinks — they are lexical string transforms
only. Each is a single-function module; they are also aggregated under
`require("lib.nvim.cross").separators`.

| Function        | Direction / effect                                   | Idempotent |
| --------------- | ---------------------------------------------------- | :--------: |
| `unify_slashes` | `\` → `/` (force forward-slash form)                 |     ✓      |
| `normalize`     | → the **current OS's** native separator              |     ✓      |
| `collapse_dots` | simplify `.`/`..` and repeated separators (segments) |     ✓      |
| `has_win_sep`   | predicate: does it start with a `C:\` / `C:/` drive? |     —      |

`unify_slashes` and `normalize` move in **opposite** directions: use
`unify_slashes` to keep a path in `/` form regardless of OS (Neovim's API and
libuv accept `/` on Windows too); use `normalize` when you need the native
look (`\` on Windows) for display or a native tool.

## Usage

```lua
local sep = require("lib.nvim.cross").separators
-- or, tree-shake friendly, direct paths:
local collapse_dots = require("lib.nvim.cross.fs.separators.collapse_dots")

sep.unify_slashes([[a\b\c]])        --> "a/b/c"
sep.normalize("a/b/c")              --> "a\\b\\c" on Windows, "a/b/c" elsewhere
sep.has_win_sep([[E:\repos]])       --> true   (truthy match)
sep.collapse_dots("a/./b/../c")     --> "a/c"
```

## `collapse_dots(path) -> string`

Lexically collapses `.` (drop) and `..` (pop the previous segment) plus
repeated separators, returning **forward-slash** form (it unifies the input
first). It is purely textual — it never consults the filesystem, so it does
**not** resolve symlinks the way a real `realpath` would.

Invariants:

- A leading `/` (POSIX root) is preserved; a `..` at the root is a no-op.
- A `C:` (Windows drive) prefix is preserved; a `..` right after it is a no-op.
- A relative path may climb above its base — leading `..` segments are kept.

```lua
collapse_dots("/a/../../b")   --> "/b"       -- never pops past POSIX root
collapse_dots("E:/../x")      --> "E:/x"     -- never pops past the drive
collapse_dots("../a/./b")     --> "../a/b"   -- relative climb preserved
collapse_dots([[.\sub\file]]) --> "sub/file" -- backslashes unified first
```

Implementation note: the module deliberately fans the transform out into small
pure helpers (`validate`, `detect_root`, `split_segments`, `is_drive_prefix`,
`collapse_segments`, `join`) that the returned function only orchestrates, so
each step can be tested or modified in isolation.
