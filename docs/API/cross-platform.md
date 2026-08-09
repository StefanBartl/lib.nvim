# API Reference — `lib.nvim.cross.*` (cross-platform OS/process/fs helpers)

Part of the [lib.nvim API reference](README.md). 29 submodules covering OS
detection, executable/Mason lookup, clipboard, opening files with the
system default app, revealing files in the file manager, path separator
normalization, WSL path conversion, file mutation/locking, and process
spawning (three tiers: shell-string `run`, argv-only `run_argv`, and
libuv-direct `uv.*`).

The root `lib.nvim.cross` aggregator (see README) wires up
`cross.is_windows`, `cross.executable`, `cross.fs`, `cross.separators`,
`cross.uv`, `cross.run`, `cross.open_default`, `cross.reveal_in_fm`. Note:
`cross.uv.fs` and `cross.fs.lock` are **not** re-exported through the
aggregate table — require them directly.

---

## OS / platform detection — `lib.nvim.cross.platform.*`

No README for this subdirectory; each is a flat single-function file,
result cached after the first call.

```
lib.nvim.cross.platform.is_windows : return function(): boolean
  -- native Windows only (excludes WSL), via uv.os_uname().sysname == "Windows_NT" + $OS fallback

lib.nvim.cross.platform.is_wsl : return function(): boolean
  -- via uv.os_uname().release markers, then $WSL_DISTRO_NAME/$WSL_INTEROP, then /proc/sys/kernel/osrelease

lib.nvim.cross.platform.is_macos : return function(): boolean
  -- uv.os_uname().sysname == "Darwin"

lib.nvim.cross.platform.is_linux : return function(): boolean
  -- Linux excluding WSL

lib.nvim.cross.platform.is : return function(platform?: string): boolean|string
  -- no argument -> detected platform name; with a name -> whether it matches
  -- detection order: wsl -> windows -> macos -> linux (unknown falls back to "linux")
```

---

## Executable / Mason binary lookup

### `lib.nvim.cross.executable` (see README)
PATH resolution and Mason-managed binary lookup — consolidates a pattern
independently re-implemented in several plugins (open.nvim's
`util.find_exec`, dap.nvim's `utils.executable`).

```
M.exists(name: string): boolean
M.path(name: string): string|nil
M.find(name_or_candidates: string|string[]): string|nil
M.mason_bin(package_name: string): string|nil
  -- resolves stdpath("data")/mason/bin/<name>, .cmd suffix on native Windows, confirmed via uv.fs_stat
```

---

## Clipboard

### `lib.nvim.cross.copy_to_clipboard` (see README)
Cross-platform clipboard write. Tries Neovim's `+` register first, then an
OS-appropriate external tool (`pbcopy` on macOS; `wl-copy`/`xclip`/`xsel`
on Linux depending on Wayland/X11; PowerShell `Set-Clipboard` on native
Windows; `clip.exe` on WSL). Always pipes `text` via **stdin**, never
shell-interpolated.

```
return function(text: string): boolean
```

---

## Open with default app / reveal in file manager

### `lib.nvim.cross.open_default` (see README)
Opens a path or URL with the system's default registered application.
Windows → `explorer.exe <target>` (not `cmd.exe /C start`, which truncates
URLs with unescaped `&`); WSL → URL straight to `explorer.exe`, a
filesystem path converted via `wslpath -w` first, falling back to
`xdg-open`; macOS → `open`; Linux → `xdg-open`. Upstreamed from
open.nvim's `handlers/default.lua`.

```
return function(target: string): boolean ok, string|nil err
```

### `lib.nvim.cross.reveal_in_fm` (see README)
Shows a path **in** the system file manager rather than opening it with
its registered app. A directory is always navigated into; a file is either
selected in its parent (`reveal = true`, default) or its parent is opened
without selecting. Windows/WSL route through a sibling PowerShell script
(`win_reveal.ps1`, via `Shell.Application` COM + `AttachThreadInput`) to
bring the resulting Explorer window to the foreground. macOS uses
`open -R`/`open`; Linux tries `xdg-open`, `nautilus`, `nemo`,
`dolphin --select`, `thunar`, `caja`, `pcmanfm` in order. Consolidates
open.nvim's `handlers/filemanager.lua` and filetree.nvim's
`features/system/open_in_fm`.

```
return function(target: string, opts?: Lib.Cross.RevealInFm.Opts): boolean ok, string|nil err
```
`opts`: `reveal?` (default `true`), `command?` (launcher override, skips
platform dispatch), `reuse?` (Windows/WSL only — navigate an existing
Explorer window instead of opening a new one).

---

## Filesystem — cwd, path expansion, mutation, locking, separators, WSL conversion

### `lib.nvim.cross.fs._cwd` (see README)
```
return function(): string   -- libuv cwd, vim.fn.getcwd() fallback
```

### `lib.nvim.cross.fs.expand_path` (see README)
Expands `~`, `$VAR`/`${VAR}` (POSIX), and `%VAR%` (Windows) in a raw path
string. Pure string expansion — does **not** normalize separators or
resolve `.`/`..`.

```
return function(path: string): string
```

### `lib.nvim.cross.fs.mutate` (see README)
Injection-safe file mutation primitives built directly on libuv (no shell)
— safe for untrusted/user-controlled paths. Every mutation routes through
`M.retry`, which re-attempts on transient sharing errors
(`EPERM`/`EACCES`/`EBUSY`) with escalating backoff (`vim.wait`-based).

```
M.defaults: Lib.Cross.Fs.Mutate.RetryOpts   -- { attempts, backoff_ms, on_retry }
M.retry(op: fun(): boolean|nil, string|nil, opts?): boolean ok, string|nil err
M.delete_file(path: string, opts?): boolean ok, string|nil err
M.copy_file(src: string, dst: string, opts?): boolean ok, string|nil err
M.rename_file(src: string, dst: string, opts?): boolean ok, string|nil err
M.mkdir_p(path: string, opts?): boolean ok, string|nil err
```

### `lib.nvim.cross.fs.lock` (see README)
Diagnoses *who* is holding a file open on Windows (Restart Manager
`rstrtmgr.dll` via a generated PowerShell/`Add-Type` C# shim) — the
diagnostic counterpart to `fs.mutate`.

```
M.supported(): boolean               -- true on Windows
M.probe(path: string): boolean ok, string|nil err   -- synchronous; renames the file aside and back
M.who(path: string, cb: fun(holders: {pid, name, app}[]|nil, err: string|nil))   -- async, Windows-only
M.report(path: string, cb: fun(lines: string[]))    -- pre-rendered human-readable report
```

### `lib.nvim.cross.fs.wslpath` (see README)
Converts paths between WSL(unix) and Windows forms via the `wslpath`
binary. Only meaningful inside a WSL session; returns `nil` elsewhere.
Blocking (`run_argv.run_blocking_captured`, no shell). Upstreamed from
three independent copies across open.nvim.

```
M.to_win(unix_path: string): string|nil
M.to_unix(win_path: string): string|nil
```

### Path separators — `lib.nvim.cross.fs.separators.*`
Five small, **pure** string transforms (no filesystem access, no `~`/env
expansion, no symlink resolution). See parent README.

```
lib.nvim.cross.fs.separators.unify_slashes : return function(path: string): string
  -- every \ -> / (fixed direction); does not collapse repeats; asserts on non-string

lib.nvim.cross.fs.separators.normalize : return function(path: string): string|nil
  -- rewrites every separator to the current OS's native form (opposite direction from unify_slashes)

lib.nvim.cross.fs.separators.collapse_dots : return function(path: string): string
  -- lexically collapses ./ .. segments and repeated separators, unifying to /
  -- preserves POSIX root / and Windows C: prefix; known gap: no UNC-prefix special-casing

lib.nvim.cross.fs.separators.drive_upper : return function(path: string): string
  -- uppercases a bare Windows drive-letter prefix; no-op on POSIX/UNC/relative paths

lib.nvim.cross.fs.separators.has_win_sep : return function(s: string): string|nil
  -- predicate: starts with a Windows drive prefix + separator? returns matched substring, not strict boolean
```

---

## Process spawning (shell-string runners)

### `lib.nvim.cross.run` (see README)
Shell selection plus shell-string runners: picks a platform-appropriate
shell, runs a single command **string** through it (async, blocking, or
detached). For argv-based execution with no shell, see `run_argv`.
`open_default` is built directly on `run_detached`.

```
M.shell(): OsShell
  -- { prog = "powershell", args = {...}, is_powershell = true } on native Windows,
  -- else { prog = "sh", args = { "-lc" }, is_powershell = false }
M.run(cmd: string, cb: fun(ok: boolean, res: OsRunResult))
  -- async; vim.system when available, else jobstart; res = { code, signal, stdout, stderr }
M.run_blocking(cmd: string): OsRunResult
M.run_detached(argv: string[]): boolean ok, string|nil err
  -- fire-and-forget; Windows/WSL routes through jobstart(detach=true) (vim.system unreliable for GUI there)
```

### `lib.nvim.cross.run_argv` (see README)
Low-level argv-based process runner with stdin support, no shell involved.
Blocks the caller.

```
M.run_blocking(cmd: string[], input?: string): boolean, string|nil
M.run_blocking_captured(cmd: string[], input?: string): boolean ok, string output
  -- like run_blocking, but always also returns captured stdout, success or failure
```

---

## Process spawning (libuv-backed primitives) — `lib.nvim.cross.uv.*`

### `lib.nvim.cross.uv.fs` (see README)
```
return function(): string   -- cwd via libuv (duplicate body of cross.fs._cwd); NOT wired into the aggregate table
```

### `lib.nvim.cross.uv.spawn_command` (no README)
Cross-platform shell-command runner built on raw `uv.spawn` (wraps with
`cmd.exe /c` on Windows, `/bin/sh -c` elsewhere).

```
return { spawn_project_command = function(cmd: string, opts: table): uv.uv_process_t? }
```
`opts`: `cwd?`, `args?`, `stdio?`, `on_exit?: fun(code, signal)`.

### `lib.nvim.cross.uv.spawn_shell_command` (no README)
Similar shell-command spawner, taking `cmd`/`args` separately.

```
return function(cmd: string, args: string[], opts: table): uv.uv_process_t?
```

### `lib.nvim.cross.uv.spawn_capture` (see README)
Async spawn of an argv command (no shell) with buffered stdout/stderr
capture and an optional timeout. On timeout the process is killed
(`sigkill`), result settles `timed_out = true`. `on_done` always dispatched
via `vim.schedule`.

```
return function(argv: string[], opts?: { timeout_ms?, cwd?, env? }, on_done: fun(result: { ok, code, signal, stdout, stderr, timed_out }))
```

### `lib.nvim.cross.uv.spawn_stream` (see README)
Async spawn with **line-by-line** streaming of stdout/stderr and optional
timeout — use when output must be consumed while the process is still
running. Line callbacks run in a **fast event context** (raw libuv read
callback — `E5560` territory for most `vim.fn`/`vim.api`); `on_exit` is
`vim.schedule`-dispatched.

```
return function(argv: string[], opts?: Lib.Cross.Uv.SpawnStream.Opts, on_line: fun(line: string), on_exit?: fun(result)): (kill: fun()|nil)
```
`opts`: `timeout_ms?`, `cwd?`, `env?`, `on_stderr_line?`, `kill_signal?` (default `"sigterm"`).

### `lib.nvim.cross.uv.wait_until` (see README)
Polls a predicate on a libuv timer until true or a max attempt count is
reached. Generic — not tied to any specific fs/process use case.

```
return function(predicate: fun(): boolean, opts?: { interval_ms?, max_attempts? }, cb: fun(ok: boolean))
  -- defaults: interval_ms = 100, max_attempts = 50
```
