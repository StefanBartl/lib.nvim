# `lib.nvim.diff.word_ranges`

The spans that changed between two **single lines**, for highlighting what
changed inside a changed line. [`lib.lua.diff`](../../../lua/diff/README.md)
works on arrays of lines; this module reuses Neovim's own diff
(`vim.text.diff`, before 0.12 `vim.diff`) instead of a second implementation.

```lua
local word_ranges = require("lib.nvim.diff.word_ranges")

local r = word_ranges("local x = 1", "local y = 1", "histogram")
-- r.a == { { 6, 7 } }   0-based, end-exclusive byte ranges in the old text
-- r.b == { { 6, 7 } }   ... and in the new text
```

`word_ranges(a, b, algorithm?)` returns `{ a = ranges, b = ranges }` or `nil`.

- **Granularity:** a code point. Both lines are exploded into a synthetic
  document with one "line" per code point, diffed with `result_type =
  "indices"` and mapped back to byte offsets, so a range never starts or ends
  inside a multi-byte character. A byte that is no part of a well-formed
  sequence (a stray byte, NUL) is a unit of its own. A line feed or carriage
  return inside the text is an ordinary unit as well; the function is meant for
  single lines and never throws for any input.
- **Ranges:** `{ from, to }`, 0-based, end-exclusive, in order. A pure
  insertion has ranges on `b` only, a pure deletion on `a` only. Equal strings
  give two empty lists.
- **`algorithm`:** `"myers"` (default), `"minimal"`, `"patience"` or
  `"histogram"`, handed to the diff as it is.
- **`nil`:** an argument that is not a string, or a diff that failed. It never
  throws.

"Word" is the name of the use (intra-line highlighting), not the unit: the
diff runs per code point, so `"quick"` -> `"quack"` marks one letter. Group
neighbouring ranges yourself if you want whole words.
