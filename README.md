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
share a single set of helpers as a [lazy.nvim](https://github.com/folke/lazy.nvim)
dependency instead of each carrying its own copy. It has **no third-party
dependencies** — only `vim` and itself.

---

## Table of contents

- [Documentation](#documentation)
- [What it does](#what-it-does)
- [Around it](#around-it)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quickstart](#quickstart)
- [End-user commands](#end-user-commands)
- [Health check](#health-check)
- [Contributing](#contributing)
- [Feedback](#feedback)
- [License](#license)

---

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
- [Architecture](docs/architecture.md) — the `lib.lua.*` / `lib.nvim.*` split and the rule behind it.
- [Installation](docs/installation.md) — plugin dependency vs. config-wide bootstrap.
- [Configuration](docs/configuration.md) — the aggregator strategies and their defaults.
- [Workflow](docs/WORKFLOW.md) — building a plugin on top: which module for which job.
- [Bindings](docs/BINDINGS.md) — the deliberately small user command and autocommand surface.
- [Health](docs/health.md) — what `:checkhealth lib` reports.
- [Contributing](docs/CONTRIBUTING.md) — ground rules, repository layout, and how to add a module.
- [Test-runner templates](templates/README.md) — resolving `lib.nvim` in a dependent plugin's own headless test suite.

`:help lib.nvim` is the same reference inside the editor — see
[docs/help.md](docs/help.md) for how the tags are generated.

### Not in this repository

[Ecosystem architecture](https://github.com/StefanBartl/documentation.nvim/blob/main/docs/ECOSYSTEM.md)
— where docs, static analysis and runtime each belong across the four pieces
this library is the bottom of (`lib.nvim`, `documentation.nvim`,
`runtime-analysis.nvim`, `mdview.nvim`), and the rule that decides what moves
down here and what does not.

---

## What it does

This is a library, not a feature plugin: almost nothing here happens on its
own. It is the layer a plugin author requires so that the same problem is not
solved a fourth time in a fourth repository.

| Namespace | Contains |
| --- | --- |
| `lib.lua.*` | Editor-independent Lua: tables, strings, numerals, time, JSON and YAML, classes, memoization, diffing, error handling, UUIDs |
| `lib.nvim.*` | Everything that needs `vim`: buffers, windows and tabs, filesystem, git, async and debounce, notifications, logging, treesitter, selections, terminals, caches, stores |
| `lib.nvim.ui` | The themed UI layer: the `kit` toolkit, list rendering, highlight helpers, nerd-font detection and statusline pieces — one look across sibling plugins instead of five |
| `lib.nvim.bindings` | Named keymap actions, and `usercmd.composer`: the subcommand-verb builder every sibling plugin's `:Command <sub>` grammar is built on |
| `lib.nvim.deps` | Declared optional external tools per plugin, and the popup, report and install command that go with them |
| `lib.strategies` | How the `lib` aggregator resolves: eager, lazy, metatable, with optional telemetry |

Modules are requireable one by one, so a plugin that needs one helper does not
load the rest. The aggregator exists for convenience, not as the entry point.

> **Compatibility, stated plainly.** This library tracks its author's own
> Neovim setup, and it stays in sync with *those* plugins by construction.
> Anyone else is welcome to use it, but the API is not held stable for external
> consumers and modules may be renamed or removed without a deprecation period.
> If you depend on it, pin a commit through your plugin manager's lockfile and
> upgrade deliberately.

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

## Requirements

| | |
| --- | --- |
| Neovim | **0.10+** |
| Third-party plugins | none — only `vim` and itself |

Individual modules reach for external tools where one exists (git, a system
package manager for `lib.nvim.deps`), and every one of them is detected at
runtime and degrades to nothing when absent.

---

## Installation

```lua
-- lazy.nvim
{
  "StefanBartl/lib.nvim",
  lazy = true,
}
```

Usually you do not install it directly at all — a plugin that needs it declares
it, and lazy.nvim resolves it once:

```lua
{
  "you/my-plugin.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
}
```

The one case that needs more is a config-wide bootstrap, where `lib` has to be
callable before lazy.nvim has finished loading specs.
[docs/installation.md](docs/installation.md) has that variant and the other
plugin managers.

---

## Quickstart

Require the module you need. Direct requires are the normal path — they are
tree-shake friendly and say in the call site exactly what is being used:

```lua
local notify = require("lib.nvim.notify")
local tables = require("lib.lua.tables")
```

Then, if you would rather have one handle:

```lua
local lib = require("lib")
lib.notify(...) -- -> lib.nvim.notify
```

Which strategy the aggregator uses to resolve those lookups — eager, lazy or
metatable — is [docs/configuration.md](docs/configuration.md).
[docs/usage.md](docs/usage.md) has the rest of the patterns, and
[docs/WORKFLOW.md](docs/WORKFLOW.md) answers the other question: which module
for which job when building a plugin on top.

---

## End-user commands

Most of `lib.nvim` is Lua modules for plugin authors, but it also registers a
few commands directly, opt-in via `require("lib.nvim_usrcmds").setup(opts)`:

| Command | Does |
| --- | --- |
| `:Lib helptags` | Regenerate all helptags now |
| `:Lib cwd-here` (= `:CwdHere`) | `lcd` to the current buffer's directory |
| `:Lib ps-profile` (= `:PowershellProfile`, Windows) | Open the active PowerShell profile in Neovim |
| `:Lib deps show <plugin.nvim>` | Report which of a dependent plugin's optional external tools are missing, and why they matter |
| `:Lib deps status` | The same across **every** plugin at once — the view for a freshly rolled-out config |
| `:Lib deps install [plugin.nvim]` | Compose and confirm an install command for what's missing — one plugin's, or everything |

The `deps` system behind them is what every sibling plugin's "declared,
installable external tools" popup comes from — see
[`lib.nvim.deps`](lua/lib/nvim/deps/README.md). `usercmd.composer`, the
subcommand-verb builder those same plugins build their own command grammar on,
lives here too — see
[`lib.nvim.bindings.usercmd.composer`](lua/lib/nvim/bindings/usercmd/composer/README.md).

---

## Health check

```vim
:checkhealth lib
```

Five sections: the environment, the configured aggregator strategy, whether a
representative set of modules resolves, the aggregator itself, and the
registered loggers. [docs/health.md](docs/health.md) has the detail.

---

## Contributing

Clone the repository and either symlink it or add it to your runtime path.
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) has the ground rules and the
repository layout; [docs/conventions.md](docs/conventions.md) is the module
layout rule a new module has to satisfy, and
[docs/architecture.md](docs/architecture.md) says which namespace it belongs in.

Pull requests very welcome.

---

## Feedback

Your feedback is very welcome. Use the
[issue tracker](https://github.com/StefanBartl/lib.nvim/issues) to report bugs,
suggest features or ask usage questions; anything more open-ended fits a
[discussion](https://github.com/StefanBartl/lib.nvim/discussions).

If you find this library useful, a ⭐ on GitHub supports its development.

---

## License

MIT — see [LICENSE](LICENSE).
