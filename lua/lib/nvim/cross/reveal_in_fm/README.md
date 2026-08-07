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

- **Windows (native)**: `explorer.exe /select,<path>` for a revealed file,
  `explorer.exe <dir>` otherwise. The path is converted to backslashes
  first — explorer.exe does not reliably accept forward slashes, and
  `/select,C:/x/y` in particular opens the wrong folder instead of failing.
  `/select,` and the path are a single argv entry: a space after the comma
  makes explorer.exe drop the path and open Documents.
- **WSL**: the same, after converting the path with `wslpath -w`. When the
  path has no Windows-side equivalent, falls back to the Linux managers
  below.
- **macOS**: `open -R <file>` / `open <dir>`.
- **Linux**: the first manager found on PATH, from `xdg-open`, `nautilus`,
  `nemo`, `dolphin --select`, `thunar`, `caja`, `pcmanfm`. Revealing a file
  skips `xdg-open` and `pcmanfm` — handing `xdg-open` a file would launch
  that file's default *application*, not a file manager, which is the one
  failure mode users read as "the plugin is broken". With no select-capable
  manager installed, the parent directory is opened instead.

The resolved command is always spawned detached via
[`lib.nvim.cross.run.run_detached`](../run/README.md).

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

## See also

- [`lib.nvim.cross.open_default`](../open_default/README.md) — open with the
  registered application instead
- [`lib.nvim.cross.fs.wslpath`](../fs/wslpath/README.md) — the WSL path
  conversion used here
