# lib.nvim

> Reusable Lua/Neovim helper library — one tested base for your own plugins.

`lib.nvim` is extracted from a private Neovim configuration so that personal
plugins can share a single, tested set of helpers as a [lazy.nvim] dependency.
It has **no third-party dependencies** — only `vim` and itself.

> **Status: early.** The API is not yet stable. Module paths may change before
> `v1.0.0`.

## Table of contents

- [Design](#design)
- [Installation](#installation)
- [Usage](#usage)
- [Namespaces & modules](#namespaces--modules)
- [Configuration](#configuration)
- [Health](#health)
- [Conventions](#conventions)

---

## Design

The library is split by responsibility into three namespaces:

| Namespace    | Purpose                                                      | `vim` API |
| ------------ | ----------------------------------------------------------- | --------- |
| `lib.lua.*`  | General, **editor-independent** Lua helpers                 | no        |
| `lib.nvim.*` | **Neovim-specific** helpers (adapters onto the `vim` API)   | yes       |
| `lib.vim.*`  | Optional **classic-Vim** implementations, API-compatible    | `vim.fn`  |

**Guiding rule:** anything that does not need the `vim` API belongs in `lib.lua.*`. `lib.nvim.*` is merely an adapter onto Neovim. `lib.vim.*` mirrors `lib.nvim.*` with a compatible signature for classic Vim where feasible.

This keeps the generic parts independently testable and reusable, and they can later move into a dedicated `lib.lua` repository.

---

## Installation

[lazy.nvim], standalone:

```lua
{ "StefanBartl/lib.nvim", lazy = true }
```

As a dependency of your own plugins:

```lua
{
  "XY/my-plugin.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
}
```

---

## Usage

Direct module paths are recommended in plugin code (tree-shake friendly):

```lua
local notify = require("lib.nvim.notify")
local tables = require("lib.lua.tables")
local map    = require("lib.nvim.map")
```

Or via the aggregator, which resolves keys lazily on first access:

```lua
local lib = require("lib")
lib.notify          -- -> lib.nvim.notify
lib.map             -- -> lib.nvim.map
lib.is_windows()    -- -> lib.nvim.cross.platform.is_windows
```

---

## Namespaces & modules

### `lib.lua.*` — Lua

| Module             | Contents                                                |
| ------------------ | ------------------------------------------------------- |
| `lib.lua.tables`   | array / dict / set / functional / safe / unique / `with`|
| `lib.lua.strings`  | trim, split/join, case conversion, padding, slugify, …  |
| `lib.lua.functions`| meta helpers: noop, identity, const, raise, …           |
| `lib.lua.time`     | time / diff calculation                                 |
| `lib.lua.json`     | decode helpers (string array)                           |
| `lib.lua.memo`     | memoization                                             |
| `lib.lua.lazy`     | lazy-`require` proxy                                     |

### `lib.nvim.*` — Neovim

| Module                 | Contents                                            |
| ---------------------- | --------------------------------------------------- |
| `lib.nvim.notify`      | notify wrapper + log-level resolution               |
| `lib.nvim.map`         | keymap helpers                                      |
| `lib.nvim.usercmd`     | user-command helpers                                |
| `lib.nvim.autocmd`     | autocmd / augroup helpers                           |
| `lib.nvim.buffer`      | buffer helpers (`insert_lines`, `is_markdown_buf`)  |
| `lib.nvim.buf_win_tab` | buffer / window / tab utilities                     |
| `lib.nvim.window`      | window helpers                                      |
| `lib.nvim.ui`          | `hover_select`, highlight helpers                   |
| `lib.nvim.fs`          | path / filesystem helpers (`vim.fs` / `uv`)         |
| `lib.nvim.cross`       | cross-platform: OS detection, run/argv, clipboard   |
| `lib.nvim.normalize`   | path / value normalization                          |
| `lib.nvim.git`         | git helpers                                         |
| `lib.nvim.terminal`    | terminal-buffer helpers                             |
| `lib.nvim.require`     | safe / dir / lazy require                           |
| `lib.nvim.lua_ls`      | LuaLS: module path, `@module` annotation            |
| `lib.nvim.core`        | misc Neovim helpers (`has_exec`, `simple_echo`)     |

### `lib.vim.*` — classic Vim

Mirrors the public API of `lib.nvim.*`. Where a port onto `vim.fn`/Vimscript is feasible there is a real implementation; otherwise an adapter with the identical signature raises a clear not-implemented error. See [`doc/vim-parity.md`](doc/vim-parity.md) for the porting status.

---

## Configuration

The only runtime choice is which aggregator strategy `require("lib")` uses. All strategies expose the same surface; they differ only in *when* submodules load. Configure **before** the first `require("lib")`:

```lua
require("lib.config").setup({ strategy = "lazy" })
local lib = require("lib")
```

| `strategy`             | Behaviour                                              |
| ---------------------- | ------------------------------------------------------ |
| `"metatable"` (default)| per-key proxy; a submodule loads on first access       |
| `"lazy"`               | eager key registry; submodules load on first access    |
| `"eager"`              | every submodule is required up-front                   |

Direct module paths ignore this setting and are always the most efficient way to consume the library.

### Default strategy

`require("lib")` uses the "metatable" strategy as default:

```lua
require("lib")
local lib = require("lib")
```

---

## Health

```vim
:checkhealth lib
```

Reports the Neovim version, the configured strategy, whether a representative set of modules resolves, and the `lib.vim` parity status.

---

## Conventions

- One module per directory with `init.lua`; module path == directory path.
- `---@module 'lib.<namespace>.<path>'` as the first line of every file.
- LuaLS type definitions (`@class`, `@alias`, standalone `@type`) live in `@types/` files, never inline in the source module.
- Internal (non-public) modules are prefixed with `_` or live under `internal/`; everything else is part of the public API.

---
