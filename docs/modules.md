# Namespaces & modules

## `lib.lua.*` — Lua

| Module             | Contents                                                |
| ------------------ | ------------------------------------------------------- |
| `lib.lua.tables`   | array / dict / set / functional / safe / unique / `with`|
| `lib.lua.strings`  | trim, split/join, case conversion, padding, slugify, …  |
| `lib.lua.functions`| meta helpers: noop, identity, const, raise, …           |
| [`lib.lua.time`](../lua/lib/lua/time/diff/README.md) | time / diff calculation ([`:help`](../doc/lib.nvim-time_diff.txt)) |
| `lib.lua.json`     | decode helpers (string array)                           |
| [`lib.lua.memo`](../lua/lib/lua/memo/README.md) | memoization                          |
| [`lib.lua.lazy`](../lua/lib/lua/lazy/README.md) | lazy-`require` proxy                 |

## `lib.nvim.*` — Neovim

| Module                 | Contents                                            |
| ---------------------- | --------------------------------------------------- |
| [`lib.nvim.notify`](../lua/lib/nvim/notify/README.md) | notify wrapper + log-level resolution |
| `lib.nvim.map`         | keymap helpers                                      |
| [`lib.nvim.usercmd`](../lua/lib/nvim/usercmd/composer/README.md) | user-command helpers: `create` + [`composer`](../lua/lib/nvim/usercmd/composer/README.md) (subcommand verbs, completion, docgen — [`:help`](../doc/lib.nvim-composer.txt)) |
| `lib.nvim.autocmd`     | autocmd / augroup helpers                           |
| `lib.nvim.buffer`      | buffer helpers (`insert_lines`, `is_markdown_buf`, `open_background`) |
| `lib.nvim.buf_win_tab` | buffer / window / tab utilities                     |
| [`lib.nvim.window`](../lua/lib/nvim/window/README.md) | overlay/float helpers: `make_scratch`, `nice_quit`, `set_title`, `close_on_focus_lost`, `center`, `attach` ([`:help`](../doc/lib.nvim-window.txt)) |
| [`lib.nvim.ui`](../lua/lib/nvim/ui/hover_select/README.md) | `hover_select` ([`:help`](../doc/lib.nvim-hover_select.txt)), highlight helpers |
| `lib.nvim.fs`          | path / filesystem helpers (`vim.fs` / `uv`): [`create_entry`](../lua/lib/nvim/fs/create_entry/README.md), [`mkdirp`](../lua/lib/nvim/fs/mkdirp/README.md) (fast-event-safe `mkdir -p`), [`normkey`](../lua/lib/nvim/fs/normkey/README.md), [`project_key`](../lua/lib/nvim/fs/project_key/README.md), `path_shorten` (fit/label styles), [`find_root`](../lua/lib/nvim/fs/find_root/README.md) (glob markers, optional chain cache), `relpath`, [`open.url.system_opener`](../lua/lib/nvim/fs/open/url/system_opener/README.md) |
| [`lib.nvim.cross`](../lua/lib/nvim/cross/fs/separators/README.md) | cross-platform: OS detection, run/argv, clipboard, uv (`spawn_capture` buffered, [`spawn_stream`](../lua/lib/nvim/cross/uv/spawn_stream/README.md) line-by-line), [path separators](../lua/lib/nvim/cross/fs/separators/README.md) (`unify_slashes`, `normalize`, `collapse_dots`, `has_win_sep`, `drive_upper`) |
| [`lib.nvim.docmap`](../lua/lib/nvim/docmap/README.md) | generated module map: scans the annotated tree, checks it for documentation drift, renders HTML/Markdown/Mermaid (`:LibMap`) |
| `lib.nvim.normalize`   | path / value normalization                          |
| `lib.nvim.git`         | git helpers                                         |
| `lib.nvim.terminal`    | terminal-buffer helpers                             |
| `lib.nvim.require`     | safe / dir / lazy require                           |
| `lib.nvim.lua_ls`      | LuaLS: module path, `@module` annotation            |
| `lib.nvim.core`        | misc Neovim helpers (`has_exec`, `simple_echo`)     |
| `lib.nvim.neotree`     | neo-tree helpers: `node` (get_path / collect_nodes / extract_paths) |
| [`lib.nvim.treesitter`](../lua/lib/nvim/treesitter/guard/README.md) | `guard`: filetype allowlist gate for treesitter activation ([`:help`](../doc/lib.nvim-treesitter.txt)) |
| [`lib.nvim.system`](../lua/lib/nvim/system/README.md) | host env snapshot (`is_windows`/`is_wsl`/…, `home`, `pathsep`, `repo_base`) + Windows rpc pipe + `proc_trace` (blocking-call instrumentation for freeze diagnosis); opt-in `setup` |
| [`lib.nvim.progress`](../lua/lib/nvim/progress/README.md) | style-agnostic progress indicator: `notify`/`statusline`/`fidget`/`float` renderers, delay-guard, focus-gated cancel-with-confirm ([`:help`](../doc/lib.nvim-progress.txt)) |
| [`lib.nvim.selection`](../lua/lib/nvim/selection/README.md) | reselect a Visual line/char range after a mapping mutates it: `keep_lines`/`keep_chars` ([`:help`](../doc/lib.nvim-selection.txt)) |

## `lib.vim.*` — classic Vim

Mirrors the public API of `lib.nvim.*`. Where a port onto `vim.fn`/Vimscript is feasible there is a real implementation; otherwise an adapter with the identical signature raises a clear not-implemented error. See [`doc/vim-parity.md`](../doc/vim-parity.md) for the porting status.

## Per-module documentation

Larger modules carry their own detailed docs. Markdown references sit next to
the source (good for browsing on GitHub); `:help` pages live in [`doc/`](../doc/)
and are generated on install by your plugin manager (see [Help docs](help.md)).

**Markdown references**

- [`lib.lua.memo`](../lua/lib/lua/memo/README.md) · [`lib.lua.lazy`](../lua/lib/lua/lazy/README.md) · [`lib.lua.time.diff`](../lua/lib/lua/time/diff/README.md)
- [`lib.nvim.notify`](../lua/lib/nvim/notify/README.md) · [`lib.nvim.window`](../lua/lib/nvim/window/README.md) · [`lib.nvim.ui.hover_select`](../lua/lib/nvim/ui/hover_select/README.md)
- [`lib.nvim.system`](../lua/lib/nvim/system/README.md) · [`lib.nvim.progress`](../lua/lib/nvim/progress/README.md) · [`lib.nvim.selection`](../lua/lib/nvim/selection/README.md)
- [`lib.nvim.buf_win_tab.capture`](../lua/lib/nvim/buf_win_tab/capture/README.md) · [`lib.nvim.buf_win_tab.resize_guarded`](../lua/lib/nvim/buf_win_tab/resize_guarded/README.md)
- [`lib.nvim.fs.ignore.list`](../lua/lib/nvim/fs/ignore/list/README.md) · [`lib.nvim.fs.is_subpath`](../lua/lib/nvim/fs/is_subpath/README.md) · [`lib.nvim.fs.polymorphic_rootresolver`](../lua/lib/nvim/fs/polymorphic_rootresolver/README.md) · [`lib.nvim.fs.find_root`](../lua/lib/nvim/fs/find_root/README.md)
- [`lib.nvim.fs.create_entry`](../lua/lib/nvim/fs/create_entry/README.md) · [`lib.nvim.fs.mkdirp`](../lua/lib/nvim/fs/mkdirp/README.md) · [`lib.nvim.fs.normkey`](../lua/lib/nvim/fs/normkey/README.md) · [`lib.nvim.fs.project_key`](../lua/lib/nvim/fs/project_key/README.md)
- [`lib.nvim.fs.open.url.system_opener`](../lua/lib/nvim/fs/open/url/system_opener/README.md) · [`lib.nvim.cross.uv.spawn_stream`](../lua/lib/nvim/cross/uv/spawn_stream/README.md)
- [`lib.nvim.docmap`](../lua/lib/nvim/docmap/README.md) — generated module map ([interactive](map/index.html) · [overview](map/overview.md))
- [`lib.nvim.lua_ls.insert.module_annotation`](../lua/lib/nvim/lua_ls/insert/module_annnotation/README.md)
- [`lib.nvim.treesitter.guard`](../lua/lib/nvim/treesitter/guard/README.md)
- [`lib.nvim.usercmd.composer`](../lua/lib/nvim/usercmd/composer/README.md)

**`:help` pages**

- `:help lib.nvim` — overview hub · `:help lib.nvim-modules` — module index
- `:help lib.nvim-window` · `:help lib.nvim-hover_select` · `:help lib.nvim-time_diff` · `:help lib.nvim-progress` · `:help lib.nvim-treesitter` · `:help lib.nvim-selection` · `:help lib.nvim-composer`

See [Conventions](conventions.md) for the steps to follow when documenting a new module, and [Help docs](help.md) for how `:help` tags are generated.
