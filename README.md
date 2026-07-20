# lib.nvim

```
  _ _ _                 _
 | (_) |__   _ ____   _(_)_ __ ___
 | | | '_ \ | '_ \ \ / / | '_ ` _ \
 | | | |_) || | | \ V /| | | | | | |
 |_|_|_.__(_)_| |_|\_/ |_|_| |_| |_|
```

![version](https://img.shields.io/badge/version-0.1.0-blue.svg)
![status](https://img.shields.io/badge/status-early-orange.svg)
![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-success.svg)
![Lua](https://img.shields.io/badge/language-Lua-yellow.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg)

> Looking for a plugin to use alongside your own `lib.nvim`-based setup? Check out
> [insights.nvim](https://github.com/StefanBartl/insights.nvim), a project-analysis
> plugin (symbols, metrics, file tree, imports) from the same author.

> Reusable Lua/Neovim helper library — one tested base for your own plugins.

`lib.nvim` is extracted from a private Neovim configuration so that personal
plugins can share a single, tested set of helpers as a [lazy.nvim] dependency.
It has **no third-party dependencies** — only `vim` and itself.

> **Status: early — no stability guarantees.** This library tracks my personal
> Neovim setup. I may change, rename, or remove modules and functions at any
> time, without notice or deprecation period, and provide **no warranty of any
> kind** — use it at your own risk.
>
> I keep `lib.nvim` in sync with **my own** plugins and config, so compatibility
> *there* is guaranteed. For anyone else: you are welcome to use it, but I will
> not hold the API stable for external consumers and cannot take your use cases
> into account. If you depend on it, **pin a commit** (via your plugin manager's
> lockfile) and upgrade deliberately.

## Quickstart

As a dependency of another plugin ([lazy.nvim]):

```lua
{
  "you/my-plugin.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
}
```

Then require modules directly (tree-shake friendly) or via the aggregator:

```lua
local notify = require("lib.nvim.notify")
local lib     = require("lib")
lib.notify(...) -- -> lib.nvim.notify
```

See [docs/installation.md](docs/installation.md) for config-wide setup (needed before `lazy.nvim` finishes loading specs) and [docs/usage.md](docs/usage.md) for more usage patterns.

## Documentation

- [Architecture](docs/architecture.md) — the `lib.lua.*` / `lib.nvim.*` / `lib.vim.*` namespace split and its guiding rule.
- [Installation](docs/installation.md) — installing as a plugin dependency vs. config-wide bootstrap.
- [Usage](docs/usage.md) — requiring modules directly or via the aggregator.
- [Namespaces & modules](docs/modules.md) — full module reference for `lib.lua.*`, `lib.nvim.*`, and `lib.vim.*`, plus links to per-module docs.
- [Configuration](docs/configuration.md) — the `require("lib")` aggregator strategies and their defaults.
- [Health](docs/health.md) — using `:checkhealth lib` to verify your setup.
- [Help docs](docs/help.md) — how the `:help lib.nvim*` vimdoc tags are generated and indexed.
- [Conventions](docs/conventions.md) — module layout rules and the steps for documenting a new module.
- [Test-runner templates](templates/README.md) — copy-paste patterns for resolving `lib.nvim` in a dependent plugin's own headless test suite.

`:help lib.nvim` is also available once installed — see [docs/help.md](docs/help.md) for details.
