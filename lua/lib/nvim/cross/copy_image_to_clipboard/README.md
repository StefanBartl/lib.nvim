# `lib.nvim.cross.copy_image_to_clipboard`

Put a **PNG file on the system clipboard as an image** — what you get when you
copy a picture in a browser, ready to paste into Paint, Teams or a chat.
Asynchronous, reports through a callback.

[`copy_to_clipboard`](../copy_to_clipboard/README.md) is text-only, and
Neovim's `+` register knows nothing about images, so this always goes to an OS
tool:

| Platform | Tool |
| --- | --- |
| Windows (native) | `powershell.exe` (else `pwsh`) `-STA`, `System.Windows.Forms.Clipboard::SetImage` |
| WSL | `powershell.exe`, the path translated with `WSLENV`'s `/p` flag |
| Linux, Wayland | `wl-copy --type image/png`, the image on stdin |
| Linux, X11 | `xclip -selection clipboard -t image/png -i <file>` |
| macOS | `osascript`, the file read `as «class PNGf»` |

On Linux the tool for the detected display server is tried first, then
whichever of `wl-copy`/`xclip` is on PATH. `xsel` cannot carry images.

## The path never enters a command string

The PowerShell and AppleScript scripts are constants. The path reaches them
through the `LIB_NVIM_CLIP_IMAGE` environment variable, reaches `xclip` as one
argv element and `wl-copy` on stdin. A file name with `'`, `$`, `;`, backticks
or typographic quotes is just a file name — the same stance that fixed command
injection in `copy_to_clipboard`.

## PNG only

Checked by the file's signature, not its extension. macOS has to be told the
type and Linux announces it as `image/png`; a crop written by
`images.convert` is a PNG anyway.

## Usage

```lua
local copy_image = require("lib.nvim.cross.copy_image_to_clipboard")

copy_image("/tmp/crop.png", function(ok, err)
  if not ok then
    vim.notify(err, vim.log.levels.WARN)
  end
end)
```

`on_done(ok, err)` always runs on the main loop: once the tool has exited, or
straight away (scheduled) when the file is missing or not a PNG, or no tool is
available — `err` then names the tool to install.

`plan(abs, platform)` is the pure decision (which argv, which environment),
`detect()` the platform as it sees it; both are public for tests and for
`:checkhealth`-style reporting.
