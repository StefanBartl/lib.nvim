# lib.nvim — Documentation

`lib.nvim` is a shared library, not a feature plugin, so its documentation has
more layers than a plugin's would: the same module is described at four
different depths depending on what you are trying to do. This page says which
layer answers which question, so you don't read the wrong one.

The [repository README](../README.md) is the short version. This is the index.

## Which layer do I want?

| I want to… | Go to |
|---|---|
| see what exists at all | [modules.md](modules.md) — one line per module, links out |
| know *why* something exists and when to reach for it | [FEATURES/](FEATURES/README.md) — narrative, per theme |
| scan function signatures across a theme | [API/](API/README.md) — signature-level reference |
| read authoritative usage for one module | that module's own `README.md` under `lua/` |
| see it working in a real call site | [EXAMPLES/](EXAMPLES/README.md) — runnable scenarios |
| understand a cross-cutting problem it solves | [guides/](guides/README.md) — problem → solution essays |
| build a plugin on top of it | [WORKFLOW.md](WORKFLOW.md) — which module for which job |

The short version: **modules.md** to find it, **FEATURES/** for the why,
**API/** for the signature, the module's own README for the detail.

## Setup

| Page | What it answers |
|---|---|
| [installation.md](installation.md) | Plugin dependency, or config-wide bootstrap? |
| [usage.md](usage.md) | Require modules directly, or through the aggregator? |
| [configuration.md](configuration.md) | Which aggregator strategies exist, and their defaults. |
| [health.md](health.md) | Verifying a setup with `:checkhealth lib`. |

## Reference

| Page | What it answers |
|---|---|
| [modules.md](modules.md) | Every `lib.lua.*` and `lib.nvim.*` namespace, with links to per-module docs. |
| [API/](API/README.md) | Function signatures for every module, grouped by topic. |
| [BINDINGS.md](BINDINGS.md) | The (deliberately small) user command and autocommand surface. |
| [BINDINGS/Usercmds.md](BINDINGS/Usercmds.md) | Generated command table — produced by the composer, not edited by hand. |
| [help.md](help.md) | How the `:help lib.nvim*` vimdoc tags are generated and indexed. |

## Understanding it

| Page | What it answers |
|---|---|
| [FEATURES/](FEATURES/README.md) | Cross-cutting capabilities, written up per theme. |
| [guides/](guides/README.md) | Ecosystem-wide findings this library absorbed so nobody re-solves them. |
| [EXAMPLES/](EXAMPLES/README.md) | Runnable scenarios for the larger modules. |
| [GUIDE-ui-kit.md](GUIDE-ui-kit.md) | Full user guide for `lib.nvim.ui.kit`, the themed UI toolkit. |
| [WORKFLOW.md](WORKFLOW.md) | The plugin-author angle: which module to reach for when building on top. |
| [architecture.md](architecture.md) | The `lib.lua.*` / `lib.nvim.*` split and the rule behind it. |

## Contributing

| Page | What it answers |
|---|---|
| [conventions.md](conventions.md) | Module layout rules, and the steps for documenting a new module. |
| [../templates/README.md](../templates/README.md) | Resolving `lib.nvim` in a dependent plugin's own headless test suite. |

There is no module map in this repository. `:DocMap` builds one from the
current tree in seconds (`:DocMap full` for LuaLS-enriched detail), which is
why the generated output is gitignored rather than committed: it would be
stale by the next commit.

## Not in this repository

[Ecosystem architecture](https://github.com/StefanBartl/documentation.nvim/blob/main/docs/ECOSYSTEM.md)
— where docs, static analysis and runtime each belong across the four pieces
this library sits at the bottom of (`lib.nvim`, `documentation.nvim`,
`runtime-analysis.nvim`, `mdview.nvim`), and the rule deciding what moves down
here and what does not.
