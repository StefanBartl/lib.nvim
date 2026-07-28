# `lib.nvim.cross.run`

Shell selection and shell-string runners: pick a platform-appropriate shell,
then run a single command **string** through it (async, blocking, or
detached). For argv-based execution (no shell involved), see
`lib.nvim.cross.run_argv` instead.

## `shell() -> OsShell`

Returns `{ prog = "powershell", args = { "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command" }, is_powershell = true }`
on native Windows (not WSL), otherwise `{ prog = "sh", args = { "-lc" }, is_powershell = false }`.

## Usage

```lua
local run = require("lib.nvim.cross.run")

-- async, via vim.system when available, else jobstart
run.run("echo hi", function(ok, res)
  -- res = { code, signal, stdout, stderr }
end)

-- blocking
local res = run.run_blocking("git rev-parse HEAD")
print(res.code, res.stdout)

-- detached (fire-and-forget, e.g. launching a GUI app)
local ok, err = run.run_detached({ "explorer.exe", "C:\\" })
```

### `run(cmd, cb)`

Runs `cmd` (a shell command string) through `shell()` asynchronously. Uses
`vim.system` when available; falls back to `vim.fn.jobstart` with buffered
stdout/stderr on older Neovim. `cb(ok, res)` always fires, with
`res = { code, signal, stdout, stderr }` (all defaulted so none are `nil`).

### `run_blocking(cmd) -> OsRunResult`

Synchronous equivalent of `run`. Uses `vim.system(...):wait()` when
available; otherwise falls back to `vim.fn.systemlist()` plus
`vim.v.shell_error`, returning `stderr = "systemlist failed"` if that call
itself errors.

### `run_detached(argv) -> ok, err`

Launches `argv` (a string list, no shell string) detached from Neovim. On
Windows or WSL, routes through `vim.fn.jobstart(argv, { detach = true })`
rather than `vim.system(argv, { detach = true })`, because `vim.system`'s
process detachment is unreliable there for GUI processes (e.g.
`explorer.exe`, `notepad`) — `jobstart` with `detach = true` handles it
correctly. Elsewhere, uses `vim.system` when available, else falls back to
`jobstart` too. Returns `false, "argv must be a non-empty string list"` if
`argv` isn't a non-empty table.

`lib.nvim.cross.open_default` is built directly on `run_detached`.
