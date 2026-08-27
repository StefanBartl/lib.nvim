# `lib.nvim.cross.run.env`

Builds a deliberately **completed** environment table for subprocesses
spawned from Neovim — a guaranteed-complete `PATH` plus the
session/keyring variables an authenticated CLI needs.

## Why this exists

A subprocess started with `vim.system()`, `vim.uv.spawn()` or `jobstart()`
inherits **Neovim's own process environment** — not the environment an
interactive login shell would have. That is standard `fork`+`exec` /
`CreateProcess` semantics, not a Neovim bug, and it bites in two
independent ways:

- **`PATH` is short.** Entries added by a shell hook (`nvm`, `pyenv`,
  `rbenv`, `asdf`, `mise`, Homebrew's `shellenv`, `~/.cargo/bin`) only
  exist after `.zshrc`/`.profile` ran. Start Neovim from a window manager
  entry, a dock icon, a terminal that doesn't spawn a login shell, or a CI
  runner, and the spawned CLI is either missing or the wrong version.
- **Session-bound auth isn't an environment variable.** `gh`/`glab` read
  their token from the OS keyring, and reaching the keyring depends on a
  variable the desktop session sets — `DBUS_SESSION_BUS_ADDRESS` for
  `gnome-keyring`/`kwallet` via libsecret on Linux, the login-session
  binding on macOS, the user context on Windows. Without it the CLI
  reports "not logged in" while the token sits valid in the keyring.

`env -i <cmd>` in a shell reproduces exactly this — same failure, no
Neovim involved. Before this module every plugin that cared hand-rolled
`vim.tbl_extend("force", vim.fn.environ(), { … })`.

## Usage

```lua
local env = require("lib.nvim.cross.run.env")

-- The common case: hand a completed env to a spawn call
vim.system({ "gh", "api", "/user" }, { env = env.build() }, on_done)

-- Same thing, keeping other spawn options
vim.system({ "docker", "ps" }, env.apply({ cwd = root, text = true }), on_done)

-- Only the PATH part
vim.env.PATH = env.path({ extra_paths = { "/opt/mytool/bin" }, mason = true })

-- Diagnostics, e.g. in a :checkhealth
for _, name in ipairs(env.missing()) do
  vim.print("not inherited by Neovim: " .. name)
end
```

## API

### `build(opts?) -> table<string,string>`

`vim.fn.environ()` (or `opts.base`), with `PATH` replaced by `path(opts)`
and every known session variable filled in wherever a value can be
recovered. Writes `PATH` back under the key the base table already used —
on Windows that is `Path`, and adding a second `PATH` key would hand the
child two conflicting entries.

### `path(opts?) -> string`

`PATH` with every existing well-known binary directory guaranteed present.
Nothing inherited is dropped or reordered; candidates are appended.
Precedence: `opts.extra_paths` → Mason's `bin` (with `mason = true`) →
inherited `PATH` → login-shell `PATH` (with `login_shell = true`) →
`candidate_dirs()`. Duplicates are removed case- and
separator-insensitively on Windows.

### `candidate_dirs() -> string[]`

The platform's well-known binary directories that actually exist
(`uv.fs_stat`), in priority order — version-manager shims first (they exist
to shadow the system binary, and an interactive shell puts them in front
too), then user bin dirs, then system ones. Cached for the session.

### `session_vars() -> string[]` / `SESSION_VARS`

Known session/keyring/agent variable names for the current platform,
`SESSION_VARS.common` first. `SESSION_VARS` is keyed by the platform names
`lib.nvim.cross.platform.is()` reports; `wsl` aliases `linux`, since a WSL
userland needs the Linux session variables, not the Windows ones.

### `missing() -> string[]`

Which of those are absent from Neovim's *own* environment. This is the
honest limit of `build()`: it cannot invent a value Neovim never received.
A non-empty result is the explanation for a keyring-backed CLI failing —
and the cue to pass `login_shell = true` or an explicit `vars` entry.

### `login_shell_env(timeout_ms?) -> table|nil`

The environment of `$SHELL -lc env` (falling back to `sh`) — what an
interactive shell has after its profile ran, and the only way to recover
state Neovim's own process never received. Blocking, bounded by
`timeout_ms` (default `3000`, so a profile that blocks on a prompt or a
slow mount can't hang Neovim), cached for the session.

Returns `nil` on native Windows: there is no login-shell initialisation
step there — a Windows process receives its environment from the user
profile at creation time, which Neovim already inherited.

### `array(vars?) -> string[]`

The completed environment as `"KEY=VALUE"` strings, ready for
`lib.nvim.cross.uv.spawn_capture`'s `opts.env`: raw libuv `uv.spawn` wants
an array, but `build()` returns the `{ [key] = value }` dict shape
`vim.system`/`jobstart` want. Extracted from two byte-identical copies
(pdfport.nvim, reposcope.nvim) that each did this dict → array conversion
by hand.

```lua
spawn_capture({ "gh", "api", "/user" }, { env = env.array() }, on_done)
```

### `apply(spawn_opts?, opts?) -> table`

A copy of `spawn_opts` with `env` filled in by `build()`, everything else
untouched. An `env` already present in `spawn_opts` is folded in as
overrides, so caller-supplied variables survive.

### `clear()`

Drops the cached directory scan and login-shell probe. Call after
installing a toolchain or editing a shell profile inside a running session.

## Options

| Field | Meaning |
| --- | --- |
| `base` | Starting environment (default `vim.fn.environ()`) |
| `extra_paths` | Directories prepended to `PATH`, highest priority |
| `passthrough` | Extra variable names to carry over from `vim.env` |
| `vars` | Explicit overrides, applied last |
| `mason` | Also put Mason's `bin` directory on `PATH` (default `false`) |
| `login_shell` | Fill gaps from a POSIX login shell (blocking, cached) |
| `timeout_ms` | Timeout for the `login_shell` probe (default `3000`) |

## Related

- `lib.nvim.cross.run` — shell-string runners built on `shell()`
- `lib.nvim.cross.run_argv` — argv runners, no shell
- `lib.nvim.cross.executable` — "is this binary reachable at all?"
- Background: *Warum Subprozesse aus Neovim eine andere Welt sehen als
  deine Shell* (`WKDBooks/Development/wkdbook-Neovim/Referenz_Notes/00_cmdline/crossplatform/SubprocessEnv.md`)
