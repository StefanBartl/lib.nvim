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

### `run_blocking_captured(cmd, input?, opts?) -> ok, output`

Like `run_blocking`, but always returns captured stdout as the second value
— on both success and failure — which is the gap `run_blocking` deliberately
leaves open (it answers "did this work", not "what did it print"). Mirrors
the legacy `local out = vim.fn.system(cmd); vim.v.shell_error` idiom, just
routed through `vim.system` (no shell) when available.

**Text vs. bytes.** By default stdout is handled as *text*: `vim.system`
replaces every `\r\n` with `\n`. Right for a command's messages, wrong for a
command whose output *is the data* — `git show` of a CRLF or binary blob. Pass
`{ binary = true }` to get the bytes exactly as the process wrote them (CRLF
kept, `NUL` and non-UTF-8 bytes intact). Needs `vim.system` (Neovim 0.10+); the
legacy fallback ignores it. `lib.nvim.git.show` is the first user.

```lua
local ok, blob = run_argv.run_blocking_captured(
  { "git", "show", "HEAD:./logo.png" }, nil, { binary = true }
)
```

`lib.nvim.cross.open_default` uses `run_blocking_captured` to resolve a WSL
path via `wslpath -w`.

### Options: `binary`, `timeout_ms`, `max_output_bytes`, `env`, `cwd`

The `*_captured` and `*_result` runners take one options table:

| Option | Meaning |
| --- | --- |
| `binary` | stdout byte for byte (see above). |
| `timeout_ms` | A timer of our own, started at spawn, sends SIGTERM after this long (SIGKILL 1500 ms later for a child that ignores it). The run then ends with **exit code `124`** and `timed_out = true`, the `timeout(1)` convention — also for a child that handles SIGTERM and exits normally. On Windows the whole process tree is killed (`taskkill /T`); elsewhere only the direct child, so a grandchild keeping the output pipes open can delay their closing — the **async** runner answers at the deadline plus a short grace anyway, the blocking one returns when `wait()` gives up, which can take up to about twice the timeout plus grace when a descendant holds the pipes (never an error from an empty result). `max_output_bytes` also stops at a UTF-8 character boundary in text mode, and stderr handed back is cut at 64 KiB. |
| `max_output_bytes` | Stop the process once its stdout exceeds this many bytes: **exit code `125`** (`run_argv.OUTPUT_LIMIT_CODE`), `stdout` holds what fitted, `stderr` says why. For commands whose output is somebody else's data. |
| `env` | Extra environment variables, **merged over** the inherited environment — a name you do not set stays inherited. |
| `cwd` | Working directory of the child. |

All three need `vim.system` (Neovim 0.10+); the legacy fallback ignores them.

```lua
local ok, out = run_argv.run_blocking_captured(
  { "git", "fetch" }, nil, { timeout_ms = 60000, env = { GIT_TERMINAL_PROMPT = "0" } }
)
```

### `run_blocking_result(cmd, input?, opts?) -> result`

`run_blocking_captured` folds everything into `ok, stdout`: enough to ask "what
did it print", not enough to tell a failure's **reason**, a **timeout** and a
**spawn failure** apart — the three things a caller reporting an error to the
user needs. `run_blocking_result` returns one table instead:

```lua
local res = run_argv.run_blocking_result({ "git", "status" }, nil, { timeout_ms = 5000 })
-- { ok = false, code = 128, stdout = "", stderr = "fatal: not a git repository…", timed_out = false }
```

| Field | Meaning |
| --- | --- |
| `ok` | `code == 0` — a process **killed by a signal is not ok** |
| `code` | the exit code; `124` after `timeout_ms`; `128 + signal` when a signal killed the process; `-1` when `cmd[1]` could not be started |
| `signal` | the terminating signal, `0` if none |
| `stdout` | captured stdout |
| `stderr` | captured stderr (`""` when empty); for a spawn failure the reason; `nil` only on the legacy fallback, which cannot separate the streams |
| `timed_out` | the run was killed for `timeout_ms` (`code == 124` with a signal set; a process that exits 124 by itself is not a timeout, with or without `timeout_ms`) |

The signal row is the reason this function exists in this shape: the OS
reports **exit status 0** for a process the OOM killer or a crash took down, so
`ok = (code == 0)` alone hands a cut-short output to the caller as a valid
answer.

Blocks the caller exactly like `run_blocking_captured`; for anything that can
take longer than a few milliseconds use `run_async_captured`, which carries the
same options and reports the same four values.

### `run_async_captured(cmd, on_done, input?, opts?) -> handle`

Asynchronous counterpart to `run_blocking_captured` (same `opts`):
spawns `cmd` and hands
the outcome to `on_done(ok, output, code, stderr, signal)` instead of blocking the UI thread
(`ok` is the exit status alone, as it always was — a process killed by a signal still
reads `ok = true, code = 0`; the 5th argument `signal` is how a caller tells)
until the process exits. `run_blocking`/`run_blocking_captured` are, by a
wide margin, the biggest source of UI freezes across the plugins built on
this library — anything that can take longer than a few milliseconds
(container CLIs, PowerShell, git over the network, image tooling) belongs
here instead. `on_done` always runs on the main loop (`vim.schedule`), so
it's safe to touch buffers/windows/`vim.fn.*` from it. Falls back to
`vim.fn.system` + `vim.schedule` on Neovim without `vim.system`.

```lua
local handle = run_argv.run_async_captured({ "git", "fetch" }, function(ok, output, code)
  if not ok then
    vim.notify("fetch failed (" .. code .. "): " .. output, vim.log.levels.ERROR)
  end
end)

-- handle.stop() sends SIGTERM; no-op on the legacy (Neovim < 0.10) fallback,
-- where there is no job to kill.
```
