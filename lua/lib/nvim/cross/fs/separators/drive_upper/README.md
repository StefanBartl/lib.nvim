Uppercases a bare Windows drive-letter prefix: `"c:/repos"` → `"C:/repos"`.
A no-op on POSIX paths, UNC shares, and relative paths — only a leading
`<letter>:` is matched and rewritten. Pure string transform (`path:gsub`
on `^(%a):`): no expansion, no disk access, no separator normalization.

```lua
local drive_upper = require("lib.nvim.cross.fs.separators.drive_upper")

drive_upper("c:/repos")   --> "C:/repos"
drive_upper("C:/repos")   --> "C:/repos"  -- already upper, unchanged
drive_upper("/etc/repos") --> "/etc/repos" -- no drive prefix, unchanged
```
