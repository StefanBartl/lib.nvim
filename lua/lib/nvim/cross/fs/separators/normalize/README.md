# `lib.nvim.cross.fs.separators.normalize`

Rewrites every separator in `path` to the **current OS's** native form —
the opposite direction from `lib.nvim.cross.fs.separators.unify_slashes`,
which always forces `/` regardless of OS.

Detects Windows via `vim.uv.os_uname()`: checks `version` for a `"Windows"`
match first, falling back to `sysname` if `version` is absent. On a detected
Windows host, every `/` is rewritten to `\`. Elsewhere, every **double**
backslash (`\\`) is rewritten to `/` — a single backslash is left alone, so
a POSIX path containing a lone `\` (rare, but legal in a filename) passes
through unchanged.

Raises an assertion error if `path` is not a string; returns `nil` only if
`vim.uv.os_uname()` itself is unavailable in a way that leaves `is_windows`
false and the input contains no `\\` to rewrite — in practice this function
always returns a string for realistic inputs.

## Usage

```lua
local normalize = require("lib.nvim.cross.fs.separators.normalize")

normalize("a/b/c")     --> "a\\b\\c" on Windows, "a/b/c" elsewhere
normalize([[a\\b\\c]]) --> "a/b/c" on non-Windows (double backslashes collapsed)
```

See also `lib.nvim.cross.fs.separators.unify_slashes` for the fixed,
OS-independent `\` → `/` direction, and `lib.nvim.cross.fs.separators.collapse_dots`
for segment-level `.`/`..` simplification.
