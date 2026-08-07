# `lib.nvim.cross.reveal_in_fm`

Shows a path **in the system file manager** — Explorer, Finder, Nautilus,
Dolphin … — rather than opening it with the application registered for its
extension. That second behaviour is
[`lib.nvim.cross.open_default`](../open_default/README.md); the two are
deliberately separate modules because they are different intents that happen
to share a platform-dispatch shape.

A **directory** target is always navigated into. A **file** target is either
selected inside its parent directory (`reveal = true`, the default) or its
parent directory is opened without selecting anything (`reveal = false`).

Consolidates two independent copies of this dispatch: open.nvim's
`handlers/filemanager.lua` and filetree.nvim's `features/system/open_in_fm`
(the ad-hoc `explorer.exe` calls elsewhere — markdown.nvim, filetree's PDF
and preview paths — are *open with the default app*, i.e.
[`open_default`](../open_default/README.md), not reveal).

## Platform dispatch

- **Windows (native)**: [`win_reveal.ps1`](win_reveal.ps1), which runs
  `explorer.exe /select,<path>` for a revealed file, `explorer.exe <dir>`
  otherwise, and then **brings the resulting window to the foreground** (see
  [below](#why-windows-needs-a-powershell-step)). The path is converted to
  backslashes first — explorer.exe does not reliably accept forward slashes,
  and `/select,C:/x/y` in particular opens the wrong folder instead of
  failing. `/select,` and the path are a single argument: a space after the
  comma makes explorer.exe drop the path and open Documents.
- **WSL**: the same script through `powershell.exe`, after converting both
  the target and the script path with `wslpath -w`. When the target has no
  Windows-side equivalent, falls back to the Linux managers below.
- **macOS**: `open -R <file>` / `open <dir>`.
- **Linux**: the first manager found on PATH, from `xdg-open`, `nautilus`,
  `nemo`, `dolphin --select`, `thunar`, `caja`, `pcmanfm`. Revealing a file
  skips `xdg-open` and `pcmanfm` — handing `xdg-open` a file would launch
  that file's default *application*, not a file manager, which is the one
  failure mode users read as "the plugin is broken". With no select-capable
  manager installed, the parent directory is opened instead.

The resolved command is always spawned detached via
[`lib.nvim.cross.run.run_detached`](../run/README.md).

## Why Windows needs a PowerShell step

Spawning `explorer.exe` straight from Neovim always created the window — but
the window never came to the front, and a window nobody can see is
indistinguishable from no window at all. This is what made the Windows
behaviour look intermittently broken for a long time.

Windows only lets a process call `SetForegroundWindow` when it already owns
the foreground window. With Neovim running inside a terminal, the foreground
window belongs to the terminal host (`WindowsTerminal.exe`, `wezterm.exe`, …)
— `nvim.exe` is just a child process, so it is denied, and so is the Explorer
it spawns. The new window is therefore created *behind* everything, at most
flashing its taskbar button. Under a GUI Neovim (Neovide, nvim-qt) `nvim.exe`
**is** the foreground process, so the identical code worked there: hence the
"it works, then it doesn't" history, which tracked the frontend in use rather
than any change in this module.

`win_reveal.ps1` fixes it by locating the window Explorer opened (via
`Shell.Application` COM) and raising it with the documented
`AttachThreadInput` sequence, which is the same mechanism `WScript.Shell`'s
`AppActivate` uses internally — applied to a handle looked up directly
instead of a guessed window title.

If PowerShell or the script cannot be found, the module falls back to the
plain `explorer.exe` spawn: a window behind other windows still beats no
window.

## Usage

```lua
local reveal_in_fm = require("lib.nvim.cross.reveal_in_fm")

reveal_in_fm(vim.api.nvim_buf_get_name(0))          -- select the current file
reveal_in_fm("~/projects", { reveal = false })      -- just navigate there
reveal_in_fm(path, { command = { "dolphin", "--select" } })
```

Returns `false, err` for an empty target, an unresolvable path, or a failed
spawn.

## Options

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `reveal` | `boolean?` | `true` | Select a file inside its parent directory. `false` → open the parent without selecting. Ignored for directory targets. |
| `command` | `string \| string[]?` | — | Launcher override. The resolved path is appended as the last argument; platform dispatch is skipped entirely. |
| `reuse` | `boolean?` | `false` | Windows/WSL only. Navigate an already-open Explorer window to the target instead of opening another one. A file cannot be *selected* this way — Explorer's `Navigate2` takes a folder — so a file target reuses the window on its parent directory. Ignored when `command` is set. |

## See also

- [`lib.nvim.cross.open_default`](../open_default/README.md) — open with the
  registered application instead
- [`lib.nvim.cross.fs.wslpath`](../fs/wslpath/README.md) — the WSL path
  conversion used here
