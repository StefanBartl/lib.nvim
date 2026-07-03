# lib.nvim

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

## Table of contents

- [Design](#design)
- [Installation](#installation)
- [Usage](#usage)
- [Namespaces & modules](#namespaces-modules)
- [Configuration](#configuration)
- [Health](#health)
- [Help docs](#help-docs)
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

How you install `lib.nvim` depends on **when** it is needed.

### As a dependency of other plugins

If `lib.nvim` is only consumed *inside other plugins*, declare it as their
dependency — [lazy.nvim] loads it on demand:

```lua
{
  "you/my-plugin.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
}
```

Standalone (loaded lazily on first `require`):

```lua
{ "StefanBartl/lib.nvim", lazy = true }
```

### Config-wide use (bootstrap required)

If you use `lib.*` **directly in your own config** — in `nvim/lua/*`, `nvim/lua/plugins/*`, autocmds, mappings, etc. — it is needed **before** lazy.nvim
has even finished reading your plugin specs. A normal plugin spec is then too late.

> **Why a plain spec / `rtp:prepend` is not enough:**
> lazy.nvim installs its own > module loader during `setup()`. That loader does **not** search runtimepath entries you add afterwards, so `require("lib.*")` fails during the spec-import phase.
> You must also register `lib.nvim` on `package.path` — the C require searcher is the universal fallback that lazy does not replace.

Bootstrap it in your `init.lua`, **before** `require("lazy").setup()`, the same way lazy.nvim bootstraps itself:

```lua
-- init.lua — BEFORE require("lazy").setup(...)
local libpath = vim.fn.stdpath("data") .. "/lazy/lib.nvim"
if not (vim.uv or vim.loop).fs_stat(libpath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/StefanBartl/lib.nvim.git", libpath,
  })
end
vim.opt.rtp:prepend(libpath)
-- Required: lazy.nvim's loader ignores rtp entries added here, so also expose
-- lib.nvim via package.path (the C require searcher, which lazy does not replace).
package.path = table.concat({
  libpath .. "/lua/?.lua",
  libpath .. "/lua/?/init.lua",
  package.path,
}, ";")
```

Then add a managed spec so `:Lazy update` keeps it current. Because the
bootstrap makes it effectively always loaded, use `lazy = false`:

```lua
{ "StefanBartl/lib.nvim", lazy = false, priority = 1000 }
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
| [`lib.lua.time`](lua/lib/lua/time/diff/README.md) | time / diff calculation ([`:help`](doc/lib.nvim-time_diff.txt)) |
| `lib.lua.json`     | decode helpers (string array)                           |
| [`lib.lua.memo`](lua/lib/lua/memo/README.md) | memoization                          |
| [`lib.lua.lazy`](lua/lib/lua/lazy/README.md) | lazy-`require` proxy                 |

### `lib.nvim.*` — Neovim

| Module                 | Contents                                            |
| ---------------------- | --------------------------------------------------- |
| [`lib.nvim.notify`](lua/lib/nvim/notify/README.md) | notify wrapper + log-level resolution |
| `lib.nvim.map`         | keymap helpers                                      |
| `lib.nvim.usercmd`     | user-command helpers                                |
| `lib.nvim.autocmd`     | autocmd / augroup helpers                           |
| `lib.nvim.buffer`      | buffer helpers (`insert_lines`, `is_markdown_buf`)  |
| `lib.nvim.buf_win_tab` | buffer / window / tab utilities                     |
| [`lib.nvim.window`](lua/lib/nvim/window/README.md) | overlay/float helpers: `make_scratch`, `nice_quit`, `set_title`, `close_on_focus_lost`, `center`, `attach` ([`:help`](doc/lib.nvim-window.txt)) |
| [`lib.nvim.ui`](lua/lib/nvim/ui/hover_select/README.md) | `hover_select` ([`:help`](doc/lib.nvim-hover_select.txt)), highlight helpers |
| `lib.nvim.fs`          | path / filesystem helpers (`vim.fs` / `uv`)         |
| `lib.nvim.cross`       | cross-platform: OS detection, run/argv, clipboard   |
| `lib.nvim.normalize`   | path / value normalization                          |
| `lib.nvim.git`         | git helpers                                         |
| `lib.nvim.terminal`    | terminal-buffer helpers                             |
| `lib.nvim.require`     | safe / dir / lazy require                           |
| `lib.nvim.lua_ls`      | LuaLS: module path, `@module` annotation            |
| `lib.nvim.core`        | misc Neovim helpers (`has_exec`, `simple_echo`)     |
| `lib.nvim.neotree`     | neo-tree helpers: `node` (get_path / collect_nodes / extract_paths) |
| `lib.nvim.system`      | host env snapshot (`is_windows`/`is_wsl`/…, `home`, `pathsep`, `repo_base`) + Windows rpc pipe; opt-in `setup` |

### `lib.vim.*` — classic Vim

Mirrors the public API of `lib.nvim.*`. Where a port onto `vim.fn`/Vimscript is feasible there is a real implementation; otherwise an adapter with the identical signature raises a clear not-implemented error. See [`doc/vim-parity.md`](doc/vim-parity.md) for the porting status.

### Per-module documentation

Larger modules carry their own detailed docs. Markdown references sit next to
the source (good for browsing on GitHub); `:help` pages live in [`doc/`](doc/)
and are generated on install by your plugin manager (see [Help docs](#help-docs)).

**Markdown references**

- [`lib.lua.memo`](lua/lib/lua/memo/README.md) · [`lib.lua.lazy`](lua/lib/lua/lazy/README.md) · [`lib.lua.time.diff`](lua/lib/lua/time/diff/README.md)
- [`lib.nvim.notify`](lua/lib/nvim/notify/README.md) · [`lib.nvim.window`](lua/lib/nvim/window/README.md) · [`lib.nvim.ui.hover_select`](lua/lib/nvim/ui/hover_select/README.md)
- [`lib.nvim.buf_win_tab.capture`](lua/lib/nvim/buf_win_tab/capture/README.md) · [`lib.nvim.buf_win_tab.resize_guarded`](lua/lib/nvim/buf_win_tab/resize_guarded/README.md)
- [`lib.nvim.fs.ignore.list`](lua/lib/nvim/fs/ignore/list/README.md) · [`lib.nvim.fs.is_subpath`](lua/lib/nvim/fs/is_subpath/README.md) · [`lib.nvim.fs.polymorphic_rootresolver`](lua/lib/nvim/fs/polymorphic_rootresolver/README.md)
- [`lib.nvim.lua_ls.insert.module_annotation`](lua/lib/nvim/lua_ls/insert/module_annnotation/README.md)

**`:help` pages**

- `:help lib.nvim` — overview hub · `:help lib.nvim-modules` — module index
- `:help lib.nvim-window` · `:help lib.nvim-hover_select` · `:help lib.nvim-time_diff`

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

## Help docs

All `:help` documentation lives in the runtimepath-root [`doc/`](doc/) directory,
one file per documented module (`doc/lib.nvim-<module>.txt`), with
`doc/lib.nvim.txt` as the hub. Start at `:help lib.nvim`.

**You do not need to generate help tags yourself.** Plugin managers run
`:helptags` on a plugin's `doc/` directory automatically on install/update —
[lazy.nvim], packer and vim-plug all do this. After the next install/update the
`:help lib.nvim*` tags resolve out of the box. (The `doc/tags` index is
generated per-user and is intentionally git-ignored.)

> Help only works from the **runtimepath-root** `doc/`. A `doc/` folder nested
> inside `lua/…` is never indexed — that is why every help file lives in the
> top-level `doc/`.

---

## Conventions

- One module per directory with `init.lua`; module path == directory path.
- `---@module 'lib.<namespace>.<path>'` as the first line of every file.
- LuaLS type definitions (`@class`, `@alias`, standalone `@type`) live in `@types/` files, never inline in the source module.
- Internal (non-public) modules are prefixed with `_` or live under `internal/`; everything else is part of the public API.

### Documenting a new module

Two-tier docs, three steps — keep it mechanical so it stays easy to extend:

1. Add a per-module `README.md` next to the source (the detailed function reference).
2. For `:help`-worthy modules, add `doc/lib.nvim-<module>.txt` tagged `*lib.nvim-<module>*` (and `*lib.nvim-<module>-<fn>*` per function).
3. Wire it into the indexes: one row in the [namespace tables](#namespaces--modules) + a bullet under [Per-module documentation](#per-module-documentation), and — for help files — one `|lib.nvim-<module>|` line in the `doc/lib.nvim.txt` hub (`*lib.nvim-modules*` section).

---
