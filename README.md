> **Beta stage — active development.** This repository is past its first shape and in
> active use, but the surface is not frozen: breaking changes are still possible. Pin a
> commit or tag if you depend on it.

# lib.nvim

```
  _ _ _                 _
 | (_) |__   _ ____   _(_)_ __ ___
 | | | '_ \ | '_ \ \ / / | '_ ` _ \
 | | | |_) || | | \ V /| | | | | | |
 |_|_|_.__(_)_| |_|\_/ |_|_| |_| |_|
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-beta-orange)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey)
[![CI](https://github.com/StefanBartl/lib.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/StefanBartl/lib.nvim/actions/workflows/ci.yml)

Reusable Lua and Neovim helpers — one tested base under a whole set of plugins.
Extracted from a private Neovim configuration so that personal plugins can
share a single set of helpers as a dependency instead of each carrying its own
copy. It has **no third-party dependencies** — only `vim` and itself.

---

## Around it

> **[documentation.nvim](https://github.com/StefanBartl/documentation.nvim)** —
> reads and navigates the docs this library's conventions produce; it also holds
> the ecosystem architecture that says what belongs down here.
>
> **[insights.nvim](https://github.com/StefanBartl/insights.nvim)** — static
> analysis of a project from inside the editor, and the largest single consumer
> of the helpers here.
>
> **[runtime-analysis.nvim](https://github.com/StefanBartl/runtime-analysis.nvim)** —
> the runtime counterpart, measuring what was actually called rather than what
> the source says.
>
> Every `StefanBartl/*.nvim` plugin depends on this one. The direction never
> reverses: nothing here may require any of them.

---

## Documentation

Start at the [documentation index](docs/README.md) — `lib.nvim` describes the
same module at several depths, and the index says which one answers which
question.

**The Basics**

- [Requirements](docs/installation.md#requirements) — Neovim version, and the (lack of) third-party dependencies.
- [Installation](docs/installation.md) — plugin dependency vs. config-wide bootstrap.
- [Quickstart](docs/quickstart.md) — requiring a module directly vs. through the aggregator.

**Reference**

- [Namespaces & modules](docs/modules.md) — every `lib.lua.*` / `lib.nvim.*` module, one line each, with links to per-module docs.
- [API reference](docs/API/README.md) — function signatures across a whole theme, without opening dozens of files.
- [Configuration](docs/configuration.md) — the aggregator strategies and their defaults.
- [Bindings](docs/BINDINGS.md) — the deliberately small user command and autocommand surface, including `:Lib deps` and `:Lib helptags`.

**The Rest**

- [Features](docs/FEATURES/README.md) — cross-cutting capabilities, written up per theme: why each exists and when to reach for it.
- [Examples](docs/EXAMPLES/README.md) — runnable scenarios for the larger modules.
- [Guides](docs/guides/README.md) — ecosystem-wide findings this library absorbed so nobody has to re-solve them.
- [Architecture](docs/architecture.md) — the `lib.lua.*` / `lib.nvim.*` split and the rule behind it.
- [Workflow](docs/WORKFLOW.md) — building a plugin on top: which module for which job.
- [Health check](docs/health.md) — what `:checkhealth lib` reports.
- [Contributing](docs/CONTRIBUTING.md) — ground rules, repository layout, and how to add a module.
- [Test-runner templates](templates/README.md) — resolving `lib.nvim` in a dependent plugin's own headless test suite.
- [Feedback](https://github.com/StefanBartl/lib.nvim/issues) — bugs, feature requests and usage questions; broader discussion in [Discussions](https://github.com/StefanBartl/lib.nvim/discussions).

`:help lib.nvim` is the same reference inside the editor — see
[docs/help.md](docs/help.md) for how the tags are generated.

Not in this repository: [ecosystem architecture](https://github.com/StefanBartl/documentation.nvim/blob/main/docs/ECOSYSTEM.md)
— where docs, static analysis and runtime each belong across the four pieces
this library is the bottom of (`lib.nvim`, `documentation.nvim`,
`runtime-analysis.nvim`, `mdview.nvim`), and the rule that decides what moves
down here and what does not.

---

## License

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

lib.nvim is released under the [MIT License](https://opensource.org/licenses/MIT).
