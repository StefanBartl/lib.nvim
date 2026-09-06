# Subprocess environment

**Module:** [`lib.nvim.cross.run.env`](../../lua/lib/nvim/cross/run/env/README.md)
· **Aggregators:** `require("lib.nvim.cross").run.env`, `require("lib").spawn_env`
· **`:help`** `lib.nvim-spawn-env`
· **API:** [cross-platform.md](../API/cross-platform.md#libnvimcrossrunenv-see-readme)
· **Spec:** [`TESTS/spawn_env_spec.lua`](../../TESTS/spawn_env_spec.lua)

## The problem

A subprocess started with `vim.system()`, `vim.uv.spawn()` or `jobstart()`
inherits **Neovim's own process environment** — not the environment an
interactive login shell would have. That is standard `fork`+`exec` /
`CreateProcess` semantics on every OS, not a Neovim bug, and it is a
sharper statement than the common (wrong) shorthand "Neovim doesn't pass
environment variables on". It does — exactly the ones it holds itself, and
no more.

Neovim's own environment is complete only when Neovim was started from an
already-initialised login shell. Started from a window-manager entry, a
dock icon, a terminal emulator that spawns no login shell, a CI runner, or
as the child of a tool that already had a reduced environment, it is
missing pieces — and the child inherits exactly that gap. Two independent
causes, one symptom:

**A — `PATH` is short.** Entries assembled by a shell hook
(`nvm`, `pyenv`, `rbenv`, `asdf`, `mise`, Homebrew's `shellenv`,
`~/.cargo/bin`) only exist after `.zshrc`/`.profile` ran. The spawned CLI
is then missing entirely, or resolves to the wrong version.

**B — session-bound auth is not an environment variable.** `gh`/`glab`
read their token from the OS keyring, and reaching the keyring depends on a
variable an interactive desktop session sets: `DBUS_SESSION_BUS_ADDRESS`
for gnome-keyring/kwallet via libsecret on Linux, the login-session binding
on macOS, the user context on Windows. Without it the CLI reports "not
logged in" while the token sits valid in the keyring.

`env -i <cmd>` in a shell reproduces both failures with no Neovim involved
— the fastest way to confirm the cause is the environment, not the spawn
mechanism. Before this module every plugin that cared hand-rolled its own
`vim.tbl_extend("force", vim.fn.environ(), { … })`.

### Tool classes that hit this

| Class | Examples | Why |
| --- | --- | --- |
| Git-hosting CLIs | `gh`, `glab` | Token/login in the OS keyring |
| HTTP clients with stored credentials | `curl` (`.netrc`), `wget` | `.netrc`/cookie-jar paths depend on `HOME` |
| Container runtimes | `docker`, `podman`, `nerdctl` | Socket path/context bound to a variable or user session |
| Version-manager-managed binaries | anything behind `nvm`/`pyenv`/`rbenv`/`asdf`/`mise` | The `PATH` entry exists only after the shell hook |
| Search tools | `rg`, `fd` | Not auth, but `PATH` when not installed system-wide |

## The solution

```lua
local env = require("lib.nvim.cross.run.env")

vim.system({ "gh", "api", "/user" }, { env = env.build() }, on_done)
vim.system({ "docker", "ps" }, env.apply({ cwd = root, text = true }), on_done)
```

- `build(opts?)` — `vim.fn.environ()` with a completed `PATH` and every
  recoverable session variable filled in. `PATH` is written back under the
  key the base already used (`Path` on Windows — a second `PATH` key would
  hand the child two conflicting entries).
- `path(opts?)` — just the `PATH` string. Nothing inherited is dropped or
  reordered; existing well-known directories are appended. Precedence:
  `extra_paths` → Mason `bin` (`mason = true`) → inherited → login-shell
  (`login_shell = true`) → `candidate_dirs()`.
- `apply(spawn_opts?, opts?)` — the same, folded into a `vim.system`
  options table; a caller-supplied `env` survives as overrides.
- `candidate_dirs()` — the platform's binary directories that actually
  exist, version-manager shims first (an interactive shell puts them in
  front too). Cached.
- `login_shell_env(timeout_ms?)` — the environment of `$SHELL -lc env`,
  bounded and cached. `nil` on native Windows, which has no login-shell
  initialisation step.
- `missing()` — which known session variables Neovim itself never received.
- `clear()` — drop the cached scan and probe.

### What it deliberately cannot do

`build()` cannot invent a value Neovim never received — cause **A** is
fully fixable from inside Neovim, cause **B** is not, in general. That is
what `missing()` is for: a non-empty result *is* the explanation, and the
cue to pass `login_shell = true` or an explicit `vars` entry.

## Wired in by default: `lib.nvim.cross.run`

`cross.run`'s shell-string runners (`run`/`run_blocking`) call `env.build()`
themselves before every spawn — a plugin that only needs to run a command
**string** gets the fix without touching this module at all:

```lua
local run = require("lib.nvim.cross.run")

run.run_blocking("gh auth status")                    -- enriched by default
run.run_blocking("gh api /user", { env_opts = { login_shell = true } })
run.run_blocking("echo $PATH", { env = false })        -- opt out entirely
```

See `lua/lib/nvim/cross/run/README.md` for the full `opts.env`/`opts.env_opts`
contract. This is **not** wired into the argv-based runners
(`cross.uv.spawn_capture`/`spawn_stream`, `cross.run_argv`) — those still need
an explicit `env = env.build()`/`env.apply(...)` call.

## Adoption

**CDX:** as of this pass, `reposcope.nvim` (gh/curl/wget, via its own
`utils/spawn_env.lua` wrapper), `pdfport.nvim` (pandoc/pdftotext/ollama,
via its own `util/spawn_env.lua` wrapper), `sandbox.nvim`
(docker/podman/nerdctl, via `util/run_argv.lua`), `replacer.nvim`
(ripgrep, `rg.lua`/`gitfiles.lua`), and `pickers.nvim` (fd/rg,
`engines/snacks.lua`/`smart/search.lua`/`sources/drives.lua`) all now call
`lib.nvim.cross.run.env` directly at their argv-runner call sites. Still to
migrate: `github_stats.nvim`, which spawns via plain `vim.system` with no
`env` handling at all.

## Related

- Background write-up: *Warum Subprozesse aus Neovim eine andere Welt sehen
  als deine Shell* —
  `WKDBooks/Development/wkdbook-Neovim/Referenz_Notes/00_cmdline/crossplatform/SubprocessEnv.md`,
  which also covers the second, related Windows trap:
  `jobstart(argv, { detach = true })` does not reliably run a **console**
  program there (libuv's `DETACHED_PROCESS` leaves it without standard
  handles), which is why `lib.nvim.cross.run.run_detached` is documented as
  GUI-only.
- `lib.nvim.cross.run` — shell-string runners
- `lib.nvim.cross.run_argv` — argv runners, no shell
- `lib.nvim.cross.executable` — is the binary reachable at all?
