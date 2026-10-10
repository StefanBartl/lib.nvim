# `lib.nvim.cross.powershell`

`escape_single(s)` escapes `s` for the inside of a PowerShell single-quoted
string. PowerShell treats the ASCII `'` **and** U+2018 to U+201B as quote
characters, so all five are doubled; doubling only the ASCII one lets a file
name such as `it’s.md` close the string early.

```lua
local esc = require("lib.nvim.cross.powershell").escape_single
local script = ("Remove-Item -LiteralPath '%s'"):format(esc(path))
```

Where possible pass the value as an environment variable or an argument
instead of splicing it into the script text.
