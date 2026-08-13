# Features

Cross-cutting capabilities lib.nvim provides, written up per theme so a
reader can find "why does this exist and when do I reach for it" without
reading source. Use these when you want the narrative; use
[`docs/API/`](../API/README.md) when you want signatures, and each module's
own `README.md` for authoritative usage. See also
[`docs/WORKFLOW.md`](../WORKFLOW.md) for the plugin-author angle — which
module to reach for when you're building on top of `lib.nvim`, not just
what each one does.

`lib.nvim` is a large shared library — ~25+ of this author's other plugins
depend on it as a hard dependency, and its surface spans logging, the
subcommand-composer framework most of those plugins build their own
commands on, window/buffer helpers, a themed UI toolkit, filesystem and
cross-platform helpers, and more. Two entries below
([subprocess-env.md](subprocess-env.md), [async-directory-walk.md](async-directory-walk.md))
are essay-style problem/solution write-ups that came out of a specific
ecosystem-wide finding — a bug or platform behaviour several plugins hit
independently, which lib.nvim then absorbed so nobody has to re-solve it.
The rest are organized by theme, each file covering one area of the module
tree.

## Files

- **[LOGGING.md](LOGGING.md)** — `lib.nvim.notify` (prefixed, fast-event-safe
  notifications) and `lib.nvim.logger` (structured logging, JSONL
  persistence, crash capture, near-zero-cost kill switches).
- **[COMMANDS.md](COMMANDS.md)** — `lib.nvim.usercmd` and the `composer`
  subsystem (the most widely-used module in the library — 30+ consuming
  plugins), plus `autocmd`, `map`, `dotrepeat`, `debounce`.
- **[WINDOW_BUFFER.md](WINDOW_BUFFER.md)** — overlay/floating window helpers,
  cached window/buffer context, Visual-selection restoration, statusline
  segments, terminal-buffer helpers.
- **[FILESYSTEM.md](FILESYSTEM.md)** — working-directory management,
  root/project detection, path resolution, directory scanning (sync and
  async), ignore lists, file read/write/mutation.
- **[CROSS_PLATFORM.md](CROSS_PLATFORM.md)** — OS detection, executable/Mason
  lookup, clipboard, open/reveal, path separators, WSL conversion, and three
  tiers of process spawning with completed subprocess environments.
- **[UI_KIT.md](UI_KIT.md)** — the themed, composable `lib.nvim.ui.kit`
  toolkit: floats, forms, pickers, button-confirms, a declarative
  multi-float layout engine.
- **[INFRA.md](INFRA.md)** — persistent per-project storage, caching,
  external-dependency detection, treesitter gating, progress reporting, Git
  queries, HTTP, and config-normalization/validated-API helpers.
- **[subprocess-env.md](subprocess-env.md)** — spawned subprocesses inherit
  Neovim's own environment, not a login shell's: incomplete `PATH`,
  unreachable OS keyring. `lib.nvim.cross.run.env` builds the completed
  environment for `vim.system`/`vim.uv.spawn`/`jobstart`; `cross.run`'s
  `run`/`run_blocking` apply it by default.
- **[async-directory-walk.md](async-directory-walk.md)** — recursive
  directory scans (`collect_recursive`, and `scan_cached`/`scan_roots` built
  on it) block the main loop on large trees. Coroutine-driven `*_async`
  counterparts fix that without a callback pyramid or a general async
  framework.
