# Cross-platform helpers

`lib.nvim.cross.*` — OS detection, executable/Mason lookup, clipboard,
open-with-default-app, reveal-in-file-manager, path-separator normalization,
WSL path conversion, injection-safe file mutation, and three tiers of
process spawning. This is the namespace every plugin doing file or process
work on more than one OS should reach for first, rather than re-deriving
platform checks or shell escaping from scratch.

## Platform detection

Cached-after-first-call predicates for the four platforms this library
targets, correctly distinguishing WSL from native Linux (a common source of
bugs in hand-rolled detection).

- **Module:** `lib.nvim.cross.platform` (`is_windows`, `is_wsl`, `is_macos`,
  `is_linux`, `is`)

```lua
local cross = require("lib.nvim.cross")
if cross.is_wsl() then ... end
```

Detection order for `is()` with no argument: WSL → Windows → macOS → Linux
(unknown falls back to Linux).

## Executable and Mason binary lookup

Consolidates a pattern several plugins had independently reimplemented
(open.nvim's `find_exec`, dap.nvim's `executable`) — PATH resolution plus
Mason-managed binary lookup in one place.

- **Module:** `lib.nvim.cross.executable` (`exists`, `path`, `find`,
  `mason_bin`)

```lua
cross.executable.find({ "rg", "grep" })     -- first one that exists
cross.executable.mason_bin("stylua")        -- stdpath("data")/mason/bin/stylua(.cmd on Windows)
```

## Cross-platform clipboard write

Tries Neovim's own `+` register first, then falls back to the right
OS-specific tool (`pbcopy` on macOS; `wl-copy`/`xclip`/`xsel` on Linux
depending on Wayland/X11; PowerShell `Set-Clipboard` on native Windows;
`clip.exe` on WSL) — always via stdin, never shell-interpolated.

- **Module:** `lib.nvim.cross.copy_to_clipboard`

## Open with default app / reveal in file manager

Two related but distinct actions: launch a path/URL with its registered
default application, or show it *in* the file manager without opening it.

- **Module:** `lib.nvim.cross.open_default`, `lib.nvim.cross.reveal_in_fm`

`open_default` uses `explorer.exe <target>` on Windows (not `cmd.exe /C
start`, which truncates URLs containing an unescaped `&`), routes WSL URLs
straight to `explorer.exe` and WSL filesystem paths through `wslpath -w`
first, and uses `open`/`xdg-open` on macOS/Linux. `reveal_in_fm` selects a
file in its parent directory by default (`reveal = true`) and, on
Windows/WSL, routes through a bundled PowerShell script
(`win_reveal.ps1`, via `Shell.Application` COM) to bring the resulting
Explorer window to the foreground rather than leaving it behind other
windows.

## Path separator normalization

Five small, pure string transforms — no filesystem access, no `~`/env
expansion — for the parts of a path pipeline that must not touch disk.

- **Module:** `lib.nvim.cross.fs.separators` (`unify_slashes`, `normalize`,
  `collapse_dots`, `drive_upper`, `has_win_sep`)

`unify_slashes` always converts `\` → `/`; `normalize` goes the other
direction, rewriting to the current OS's native separator. `collapse_dots`
lexically resolves `.`/`..` segments (known gap: no UNC-prefix
special-casing).

## WSL path conversion

Converts between WSL(unix) and Windows path forms via the real `wslpath`
binary — only meaningful inside an actual WSL session, returns `nil`
elsewhere. Upstreamed from three independent copies that had accumulated
across `open.nvim`.

- **Module:** `lib.nvim.cross.fs.wslpath` (`to_win`, `to_unix`)

## Injection-safe file mutation with retry

File mutation primitives (delete/copy/rename/mkdir) built directly on libuv,
no shell — safe to call with untrusted or user-controlled paths. Every
mutation routes through a shared retry wrapper that re-attempts on
transient sharing errors (`EPERM`/`EACCES`/`EBUSY`) with escalating backoff,
the class of error a file that's briefly locked by an indexer or antivirus
scan produces.

- **Module:** `lib.nvim.cross.fs.mutate` (`delete_file`, `copy_file`,
  `rename_file`, `mkdir_p`, `retry`)

## Windows file-lock diagnosis

Diagnoses *who* is holding a file open on Windows via the Restart Manager
API (`rstrtmgr.dll`, reached through a generated PowerShell/`Add-Type` C#
shim) — the diagnostic counterpart to `fs.mutate`'s retry-and-hope, for when
a caller wants to tell the user which process to close.

- **Module:** `lib.nvim.cross.fs.lock` (`supported`, `probe`, `who`, `report`)

## Shell-string process runners

Picks a platform-appropriate shell and runs a command **string** through it
— async, blocking, or fire-and-forget detached.

- **Module:** `lib.nvim.cross.run` (`shell`, `run`, `run_blocking`,
  `run_detached`)

```lua
local run = require("lib.nvim.cross.run")
run.run_blocking("gh auth status")   -- environment enriched by default, see below
```

`run_detached` routes Windows/WSL through `jobstart(detach=true)` rather
than `vim.system`, which is unreliable for GUI-launching processes there —
documented as GUI-only for exactly this reason.

## Completed subprocess environment

- **Tab:** true
- **Module:** `lib.nvim.cross.run.env` (`build`, `path`, `apply`,
  `candidate_dirs`, `missing`, `login_shell_env`, `clear`) · also reachable
  as `require("lib").spawn_env`
- **Deep dive:** [`docs/guides/subprocess-env.md`](../guides/subprocess-env.md)

A subprocess started with `vim.system()`/`vim.uv.spawn()`/`jobstart()`
inherits **Neovim's own process environment**, not an interactive login
shell's — standard fork+exec/CreateProcess semantics, not a Neovim bug.
Neovim's own environment is complete only when it was itself started from an
already-initialized login shell; started from a window-manager entry, a
dock icon, a terminal emulator with no login-shell step, or CI, it's missing
pieces the child then inherits exactly.

Two independent causes produce the same symptom: a short `PATH` (entries a
shell hook like `nvm`/`pyenv`/`asdf`/Homebrew's `shellenv` only adds after
`.zshrc` runs), and session-bound auth that isn't an environment variable at
all (`gh`/`glab` read a token from the OS keyring, reachable only via a
session variable like `DBUS_SESSION_BUS_ADDRESS` that a non-interactive
Neovim start never received).

```lua
local env = require("lib.nvim.cross.run.env")
vim.system({ "gh", "api", "/user" }, { env = env.build() }, on_done)
```

- `build(opts?)` — `vim.fn.environ()` with a completed `PATH` and every
  recoverable session variable filled in.
- `path(opts?)` — just the `PATH` string, nothing inherited dropped or
  reordered. Precedence: `extra_paths` → Mason `bin` → inherited → login-shell
  → `candidate_dirs()`.
- `apply(spawn_opts?, opts?)` — folds the completed env into a `vim.system`
  options table; a caller-supplied `env` survives as overrides.
- `missing()` — which known session variables Neovim itself never received
  (a non-empty result *is* the explanation, and the cue to pass
  `login_shell = true`).

`cross.run`'s `run`/`run_blocking` call `env.build()` themselves before every
spawn, so a plugin that only runs a command **string** gets this fix for
free. **Not** wired into the argv-based runners (`run_argv`,
`uv.spawn_capture`/`spawn_stream`) — those need an explicit
`env.build()`/`env.apply(...)` call at the call site. See
[subprocess-env.md](../guides/subprocess-env.md) for the full write-up, including the
list of sibling plugins still migrating onto this.

## Argv process runners (no shell)

Low-level argv-based execution with stdin support and no shell
interpolation at all — for a command whose arguments must never be
re-parsed by a shell.

- **Module:** `lib.nvim.cross.run_argv` (`run_blocking`,
  `run_blocking_captured`)

## libuv-backed spawn primitives

The lowest layer: raw `uv.spawn` wrappers plus two general-purpose
primitives most callers should prefer over hand-rolling their own libuv
callbacks.

- **Module:** `lib.nvim.cross.uv` (`spawn_command`, `spawn_shell_command`,
  `spawn_capture`, `spawn_stream`, `wait_until`)

`spawn_capture` buffers stdout/stderr and supports a timeout (kills the
process and sets `timed_out = true` on expiry); `on_done` is always
`vim.schedule`-dispatched. `spawn_stream` streams stdout/stderr
**line-by-line** for output that must be consumed while the process is
still running — but its line callbacks run in a genuine fast-event context
(the raw libuv read callback), so they're `E5560` territory for
`vim.fn`/`vim.api` calls; only `on_exit` is schedule-dispatched. `wait_until`
is a generic predicate poller on a libuv timer, not tied to any specific
fs/process use case.
