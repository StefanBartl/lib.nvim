Predicate: does `s` start with a Windows drive prefix followed by a
separator, e.g. `C:\` or `E:/`? Implemented as a single Lua pattern match,
`s:match("^[A-Za-z]:[\\/]")`, and returns whatever that match yields — the
matched substring (a truthy string) on a hit, or `nil` on no match. It is
**not** a strict `boolean`; callers rely on Lua truthiness (`if
has_win_sep(s) then ...`), not `== true`.

```lua
local has_win_sep = require("lib.nvim.cross.fs.separators.has_win_sep")

has_win_sep([[E:\repos]])  --> "E:\" (truthy)
has_win_sep("C:/repos")    --> "C:/" (truthy)
has_win_sep("c:repos")     --> nil   -- no separator after the drive letter
has_win_sep("/etc/repos")  --> nil
```
