# `lib.nvim.clipboard_image`

Save the image on the system clipboard as a PNG (synchronous).

```lua
local ci = require("lib.nvim.clipboard_image")
local ok, err = ci.save("/tmp/shot.png")   -- false, "no image in the clipboard" when there is none
local tool, why = ci.tool()                -- the tool this platform would use, or the reason there is none
```

| Platform | Tool |
| -------- | ---- |
| Windows | `powershell.exe -STA` (WinForms clipboard) |
| macOS | `pngpaste` |
| Linux | `wl-paste`, else `xclip` |

Tools are detected, not assumed; a missing one is an error message. Nothing is
written when the clipboard holds no image, and the result must carry the PNG
signature. `opts.platform`, `opts.has` and `opts.system` replace the platform
check, the executable check and the process runner for specs.
