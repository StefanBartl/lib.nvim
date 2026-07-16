# `lib.lua.diff`

Line-array diff helpers, pure Lua, no `vim.*`. Two strategies for two
different needs:

- `lines`: cheap common-prefix/common-suffix trim producing a **single
  splice region** — fast, good enough when you just need "what changed"
  for e.g. deciding whether to re-render a buffer range.
- `myers`: a **correct** full line-diff producing an ordered edit script
  (`equal`/`insert`/`delete` per line) via an O(n·m) DP LCS backtrack —
  use when you need the actual line-by-line changes (e.g. a diff view).

## Usage

```lua
local diff = require("lib.lua.diff")

-- Cheap splice region
local region = diff.lines.diff({ "x", "y", "z" }, { "x", "1", "2", "z" })
-- region = { start = 2, a_end = 2, b_end = 3 }
-- meaning: a[2..2] ("y") is replaced by b[2..3] ("1","2")

local same = diff.lines.diff({ "a" }, { "a" })
-- same = nil (arrays are equal)

-- Full edit script
local script = diff.myers.diff({ "a", "b", "c" }, { "a", "x", "c" })
-- script = {
--   { op = "equal",  value = "a" },
--   { op = "delete", value = "b" },
--   { op = "insert", value = "x" },
--   { op = "equal",  value = "c" },
-- }
```

Submodules can also be required directly: `require("lib.lua.diff.lines")`,
`require("lib.lua.diff.myers")`.

## Returns

| Function       | Returns                                                            |
| -------------- | -------------------------------------------------------------------- |
| `lines.diff`   | `{ start, a_end, b_end }` (1-based, inclusive) or `nil` if equal      |
| `myers.diff`   | `{ op = "equal"\|"insert"\|"delete", value = string }[]` (ordered)   |
