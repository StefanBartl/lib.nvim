> **Alpha stage — active development.** This repository is in its development phase — breaking changes are to be expected at any time. Pin a commit or tag if you depend on it.

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
![Status](https://img.shields.io/badge/status-alpha-red)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey)

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

## End-user commands

Most of `lib.nvim` is Lua modules for plugin authors, but it also registers
a few commands directly, opt-in via `require("lib.nvim_usrcmds").setup(opts)`:

| Command | What it does |
|---|---|
| `:Lib helptags` | Regenerate all helptags now |
| `:Lib cwd-here` (= `:CwdHere`) | `lcd` to the current buffer's directory |
| `:Lib ps-profile` (= `:PowershellProfile`, Windows) | Open the active PowerShell profile in Neovim |
| `:Lib deps show <plugin.nvim>` | Report which of a dependent plugin's optional external tools are missing, and why they matter |
| `:Lib deps status` | The same across **every** plugin at once — the view for a freshly rolled-out config |
| `:Lib deps install [plugin.nvim]` | Compose and confirm an install command for what's missing — one plugin's, or everything |

The `deps` system is what every sibling plugin's "declared, installable
external tools" popup and `:Lib deps show <plugin>` come from — see
[`lib.nvim.deps`](lua/lib/nvim/deps/README.md). `usercmd.composer`, the
subcommand-verb builder every sibling plugin's own `:Command <sub>` grammar
is built on, lives here too — see
[`lib.nvim.bindings.usercmd.composer`](lua/lib/nvim/bindings/usercmd/composer/README.md).

## Documentation

Start at the [documentation index](docs/README.md) — `lib.nvim` describes the
same module at several depths, and the index says which one answers which
question.

- [Documentation index](docs/README.md) — the full map, and which layer to read for what.
- [Namespaces & modules](docs/modules.md) — every `lib.lua.*` / `lib.nvim.*` module, one line each, with links to per-module docs.
- [Features](docs/FEATURES/README.md) — cross-cutting capabilities, written up per theme: why each exists and when to reach for it.
- [API reference](docs/API/README.md) — function signatures across a whole theme, without opening dozens of files.
- [Examples](docs/EXAMPLES/README.md) — runnable scenarios for the larger modules.
- [Guides](docs/guides/README.md) — ecosystem-wide findings this library absorbed so nobody has to re-solve them.
- [Installation](docs/installation.md) — plugin dependency vs. config-wide bootstrap.
- [Workflow](docs/WORKFLOW.md) — building a plugin on top: which module for which job.
- [Test-runner templates](templates/README.md) — resolving `lib.nvim` in a dependent plugin's own headless test suite.

`:help lib.nvim` is also available once installed — see [docs/help.md](docs/help.md) for details.

### Not in this repository

[Ecosystem architecture](https://github.com/StefanBartl/documentation.nvim/blob/main/docs/ECOSYSTEM.md)
— where docs, static analysis and runtime each belong across the four pieces
this library is the bottom of (`lib.nvim`, `documentation.nvim`,
`runtime-analysis.nvim`, `mdview.nvim`), and the rule that decides what moves
down here and what does not.

## License

MIT — see [LICENSE](LICENSE).
