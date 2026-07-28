# `lib.nvim.cross.run_argv`

Low-level argv-based process runner with stdin support — no shell involved
(contrast `lib.nvim.cross.run`, which runs a shell command **string**
through a platform shell). Blocks the caller.

## Usage

```lua
local run_argv = require("lib.nvim.cross.run_argv")

local ok, err = run_argv.run_blocking({ "git", "status" })
if not ok then
  vim.notify("failed: " .. tostring(err), vim.log.levels.ERROR)
end

local ok2, output = run_argv.run_blocking_captured({ "git", "rev-parse", "HEAD" }, nil)
```

### `run_blocking(cmd, input?) -> ok, err`

Runs `cmd` (argv list) via `vim.system(cmd, { text = true, stdin = input }):wait()`
when available. `vim.system` raises synchronously if `cmd[1]` can't be
spawned at all (e.g. `ENOENT`); that case is caught via `pcall` and turned
into `false, tostring(err)` like every other failure path, rather than
letting the error escape to the caller. On success (`code == 0`) returns
`true, nil`; on a nonzero exit returns `false, stderr` (or
`"exit code " .. code"` if stderr was empty). Falls back to
`vim.fn.system(cmd, input or "")` plus `vim.v.shell_error` on Neovim
without `vim.system`.

### `run_blocking_captured(cmd, input?) -> ok, output`

Like `run_blocking`, but always returns captured stdout as the second value
— on both success and failure — which is the gap `run_blocking` deliberately
leaves open (it answers "did this work", not "what did it print"). Mirrors
the legacy `local out = vim.fn.system(cmd); vim.v.shell_error` idiom, just
routed through `vim.system` (no shell) when available.

`lib.nvim.cross.open_default` uses `run_blocking_captured` to resolve a WSL
path via `wslpath -w`.
