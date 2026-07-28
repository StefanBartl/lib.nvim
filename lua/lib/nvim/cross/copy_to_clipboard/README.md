# `lib.nvim.cross.copy_to_clipboard`

Cross-platform clipboard write, returning a plain `boolean`.

Tries Neovim's `+` register first (`vim.fn.setreg`). If that fails (e.g. no
clipboard provider configured), falls through to an OS-appropriate external
tool, with `text` always piped via **stdin** — never interpolated into a
shell command string. String interpolation into `xclip`/`wl-copy` calls was
a real command-injection bug fixed here: a `text` value containing shell
metacharacters could execute arbitrary commands.

Platform fallback order:

- **macOS**: `pbcopy`.
- **Linux (non-WSL)**: picks `wl-copy` under Wayland or `xclip`/`xsel` under
  X11, detected via `$WAYLAND_DISPLAY`/`$DISPLAY`; if the display-server
  guess doesn't pan out, falls back to trying every known tool (`wl-copy`,
  `xclip -selection clipboard`, `xsel --clipboard --input`) regardless.
- **Windows (native, not WSL)**: pipes into `Set-Clipboard` via PowerShell.
- **WSL**: `clip.exe` (resolved on PATH), with an absolute-path fallback at
  `/mnt/c/Windows/System32/clip.exe` if PATH resolution fails.

Each external-tool attempt is gated on `vim.system` existing and the binary
being resolvable on PATH (via `lib.nvim.core.has_exec`); if neither the
register write nor any applicable external tool succeeds, returns `false`.

## Usage

```lua
local copy_to_clipboard = require("lib.nvim.cross.copy_to_clipboard")

local ok = copy_to_clipboard("some text")
if not ok then
  vim.notify("clipboard copy failed", vim.log.levels.WARN)
end
```
