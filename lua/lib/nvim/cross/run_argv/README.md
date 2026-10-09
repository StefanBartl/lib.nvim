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
| `timeout_ms` | A timer of our own, started at spawn, sends SIGTERM after this long; whatever is still running 1500 ms later gets SIGKILL. The run then ends with **exit code `124`** and `timed_out = true`, the `timeout(1)` convention — also for a child that handles SIGTERM and exits normally. The **process tree** is killed: on POSIX both signals go to the child's process group (see [Process groups](#process-groups-posix)), so grandchildren such as the `git-remote-http` behind a stalled `git fetch` die with it, the output pipes close at once and the **async** runner answers right at the deadline; on Windows `taskkill /T` kills the tree. On POSIX that needs the child itself to be still running at the deadline: the descendants of a child that has **exited already**, and daemons that left the group with `setsid()`, are not signalled (a group id that no member holds may have been reused). The async runner settles at the deadline plus the 1500 ms grace period at the latest (a descendant that still holds the pipes: always on Windows, on POSIX only the two cases above) with code `124` and signal `9`, the blocking one returns when `wait()` gives up (never an error from an empty result). `max_output_bytes` also stops at a UTF-8 character boundary in text mode, and stderr is collected up to 64 KiB (the rest is read and dropped, so a process printing gigabytes there cannot fill the editor's memory). |
| `max_output_bytes` | Stop the process once its stdout exceeds this many bytes: **exit code `125`** (`run_argv.OUTPUT_LIMIT_CODE`), `stdout` holds what fitted, `stderr` says why. The SIGKILL goes to the whole process group on POSIX while the child is still running, like the timeout's. For commands whose output is somebody else's data. |
| `env` | Extra environment variables, **merged over** the inherited environment — a name you do not set stays inherited. |
| `cwd` | Working directory of the child. |

All three need `vim.system` (Neovim 0.10+); the legacy fallback ignores them.

```lua
local ok, out = run_argv.run_blocking_captured(
  { "git", "fetch" }, nil, { timeout_ms = 60000, env = { GIT_TERMINAL_PROMPT = "0" } }
)
```

### Process groups (POSIX)

A child that can be killed — every `run_async_captured` child, and every
`run_blocking_captured` / `run_blocking_result` child run with `timeout_ms` or
`max_output_bytes` — is started with `vim.system`'s `detach = true`: libuv calls
`setsid()`, the child becomes the leader of a session and process group of its
own (group id = its pid), and the kill (deadline, SIGKILL after the grace period,
output cap, `stop()`) signals that **group** (`kill(-pid)`), not just the child.
A blocking run without an armed deadline or cap (none given, or a `NaN` or negative
value, which arms nothing) cannot be killed and is not detached.
Windows detaches nothing and uses `taskkill /T`.

What detaching changes for the child (measured by hand on Linux, Neovim 0.11; the specs only check that the child leads a process group of its own, the headless runner has no controlling terminal):

- **No controlling terminal.** Opening `/dev/tty` fails at once (`ENXIO`), so a
  program that prompts there (`ssh` for a passphrase or host key, `gpg`'s
  pinentry, `git` asking for a username without `GIT_TERMINAL_PROMPT=0`) fails
  fast instead of drawing the prompt into the TUI and waiting for a key nobody
  can type. Prompts over stdin/stdout are unaffected (stdin is a pipe).
- **No terminal-generated signals** (Ctrl-C's SIGINT, the SIGHUP of a vanishing
  terminal): the child ends by its own end or by one of our kills. `:qa!` leaves a
  running child alive either way (Neovim never killed `vim.system` children), and
  does **not** wait for it: exiting Neovim took the same time with a running
  detached child as with an attached one. Closing the terminal no longer takes a
  still running child with it.
- **Group signals only for groups this module created**, and only while the group
  is provably ours: while the child is alive, or — for the SIGKILL that follows the
  deadline's SIGTERM after the grace period — when that SIGTERM went to the group
  while the child was alive (a child that exits on the SIGTERM while a descendant
  ignores it and holds the pipes). That follow-up lasts for the grace period (1.5 s)
  of the one run and ends with the SIGKILL; `stop()` and the output cap do not open
  it. For a child that has exited otherwise — on its own before the deadline, the
  cap or `stop()` came, or on an early `stop()` before a later deadline — the group
  is left alone: nobody can tell whether a member is left, and with none the group
  id may have been reused by a stranger. Its descendants then survive the timeout
  (the async runner still answers at the deadline plus the grace period, with code
  `124` and signal `9`), exactly as they did before groups were used. A pid of 0 or
  1 is never signalled as a group.
- The group kill covers descendants that stay in the group. A daemon that calls
  `setsid()` itself (or `setpgid()`) leaves it and is not reached; neither was it by
  the direct-child kill.

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

-- handle.stop() sends SIGTERM to the child's whole process group (on Windows it
-- kills the process tree); no-op on the legacy (Neovim < 0.10) fallback, where
-- there is no job to kill.
```
