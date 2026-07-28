Lexically collapses `.` (drop) and `..` (pop the previous segment) plus
repeated separators in `path`, returning **forward-slash** form (it unifies
the input first via `lib.nvim.cross.fs.separators.unify_slashes`). Purely
textual — it never consults the filesystem, so it does not resolve symlinks
the way a real `realpath` would.

Implemented as a thin orchestrator over small pure helpers (`validate`,
`detect_root`, `split_segments`, `is_drive_prefix`, `collapse_segments`,
`join`), each independently testable.

Invariants:

- A leading `/` (POSIX root) is preserved; a `..` at the root is a no-op
  (dropped, not an error).
- A `C:`-style Windows drive prefix is preserved; a `..` immediately after
  it is likewise a no-op.
- A relative path may climb above its base — leading `..` segments are kept
  when there is no root to stop at.

```lua
local collapse_dots = require("lib.nvim.cross.fs.separators.collapse_dots")

collapse_dots("/a/../../b")   --> "/b"       -- never pops past POSIX root
collapse_dots("E:/../x")      --> "E:/x"     -- never pops past the drive
collapse_dots("../a/./b")     --> "../a/b"   -- relative climb preserved
collapse_dots([[.\sub\file]]) --> "sub/file" -- backslashes unified first
```

> **Known gap:** UNC prefixes (`//server/share/...`) are not special-cased —
> `detect_root` only recognizes a single leading `/`, so a UNC path's double
> leading slash collapses to one, corrupting it. See
> `lib.nvim.cross.fs.separators` for the fuller note (no current caller in
> this repo passes UNC paths through `collapse_dots`).
