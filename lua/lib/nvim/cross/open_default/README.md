# `lib.nvim.cross.open_default`

Opens a path or URL with the system's default application — the
cross-platform equivalent of double-clicking it in a file manager (the
extension or URL scheme decides the app: PDF → PDF viewer, `.docx` → Word,
`https://` → default browser).

Upstreamed from open.nvim's `handlers/default.lua`, chosen as the most
complete of three independent copies the author had accumulated across
plugins (markdown.nvim's own copy, for one, has no WSL handling at all).

Platform dispatch:

- **Windows (native)**: `explorer.exe <target>`. Deliberately not
  `cmd.exe /C start` — `cmd.exe`'s tokenizer treats a bare `&` outside
  quotes as a command separator and silently truncates any URL/path with an
  unescaped `&` (i.e. any link with 2+ query params), since `vim.system`/libuv
  only quote an argv entry that contains whitespace. `explorer.exe` hands the
  target straight to the registered handler with no re-tokenizing.
- **WSL**: a URL goes straight to `explorer.exe`; a filesystem path is
  converted to its Windows equivalent via `wslpath -w` and then opened the
  same way; if `wslpath` fails to produce a path, falls back to `xdg-open`
  for a Linux-side file with no Windows-side equivalent, or returns
  `false, "cannot determine how to open: " .. target"` if `xdg-open` isn't
  present either.
- **macOS**: `open <target>`.
- **Linux (other)**: `xdg-open <target>`; returns `false` with an error if
  `xdg-open` isn't on PATH.

`target` is passed through `lib.nvim.cross.fs.expand_path` before dispatch
(except the WSL URL branch, which skips straight to `explorer.exe`). The
resolved command is always spawned detached via
`lib.nvim.cross.run.run_detached` — the browser/viewer keeps running after
Neovim exits.

## Usage

```lua
local open_default = require("lib.nvim.cross.open_default")

local ok, err = open_default("~/notes/report.pdf")
local ok2 = open_default("https://example.com/x?a=1&b=2")
if not ok then
  vim.notify("could not open: " .. tostring(err), vim.log.levels.WARN)
end
```

Returns `false, "empty target"` if `target` is not a non-empty string.

## `opts.on_exit`

By default the opener is spawned detached (via `lib.nvim.cross.run.run_detached`)
and the `ok` return says only that a command was *dispatched*. Pass
`opts.on_exit` to run it **attached** (via `jobstart`) and observe the real
exit code:

```lua
open_default(url, {
  on_exit = function(code)
    if code ~= 0 then
      vim.notify("opener exited " .. code, vim.log.levels.WARN)
    end
  end,
})
```

This is the one piece of surface absorbed from this repo's former, less
complete URL-opener module, removed 2026-09-06 once every caller had
migrated to this function directly.
