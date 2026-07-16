# `lib.nvim.fs.trash`

Cross-platform "send to trash/recycle bin" — not a permanent delete. Dispatches
to the OS-native mechanism: PowerShell + `Microsoft.VisualBasic.FileIO
.FileSystem` on native Windows, Finder via `osascript` on macOS, and
`gio trash` / `trash-put` on Linux (and WSL, when available). Reuses
`lib.nvim.cross.run` / `lib.nvim.cross.platform.*` rather than spawning
processes directly.

## Usage

```lua
local trash = require("lib.nvim.fs.trash")

-- Async
trash.trash("/tmp/some_file.txt", function(ok, err)
  if not ok then
    vim.notify("trash failed: " .. tostring(err), vim.log.levels.ERROR)
  end
end)

-- Blocking
local ok, err = trash.trash_blocking("/tmp/some_dir")
```

## Returns

| Function                    | Returns                  | Meaning                                   |
|------------------------------|---------------------------|--------------------------------------------|
| `M.trash(path, cb)`           | —, calls `cb(ok, err)`    | Async send-to-trash                        |
| `M.trash_blocking(path)`      | `boolean, string\|nil`    | Synchronous send-to-trash                  |

## Limitation of the Linux fallback

When neither `gio` nor `trash-put` is available, `path` is moved into
`$XDG_DATA_HOME/Trash/files` (or `~/.local/share/Trash/files`) directly via
`fs_rename`. This fallback does **not** write the accompanying `.trashinfo`
metadata that real trash implementations use, so "restore from trash" UIs may
not show the original path. This is an accepted limitation of the fallback
path only — install `gio` (part of `glib2`/GNOME) or `trash-cli` for full
fidelity.
