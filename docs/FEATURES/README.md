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
cross-platform helpers, and more. Every file here is organized by theme,
each covering one area of the module tree.

The two essay-style problem/solution write-ups that used to live here moved
to [`../guides/`](../guides/README.md) on 2026-08-26: only theme files belong
in this folder, because the parser behind the Features tab reads every `##`
in it as a feature, and an essay's own section headings were counted as
eleven features that do not exist. Both topics are still in the catalogue
below, one entry each, each linking out to its long version.

## Files

- **[LOGGING.md](LOGGING.md)** — `lib.nvim.notify` (prefixed, fast-event-safe
  notifications) and `lib.nvim.logger` (structured logging, JSONL
  persistence, crash capture, near-zero-cost kill switches).
- **[COMMANDS.md](COMMANDS.md)** — `lib.nvim.bindings.usercmd` and the `composer`
  subsystem (the most widely-used module in the library — 30+ consuming
  plugins), plus `autocmd` (incl. `autocmd.dispatcher` — one autocmd, many
  lazy-loaded, prioritized handlers), `map`, `dotrepeat`, `debounce`.
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
  queries, HTTP, count-prefixed keymaps, and
  config-normalization/validated-API helpers.
## Deep dives

Two topics have a long-form write-up beside their catalogue entry, in
[`../guides/`](../guides/README.md): the
[subprocess environment](../guides/subprocess-env.md) a spawned CLI actually
sees, and the [async directory walk](../guides/async-directory-walk.md) that
keeps a large tree off the main loop.
