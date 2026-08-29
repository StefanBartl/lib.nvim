# Namespaces & modules

For a function-signature-level index (every exported function, not just
namespace one-liners), split by topic, see [`API/README.md`](API/README.md).

## `lib.lua.*` — Lua

| Module             | Contents                                                |
| ------------------ | ------------------------------------------------------- |
| `lib.lua.tables`   | array / dict / set / functional / safe / unique / `with`|
| [`lib.lua.strings`](../lua/lib/lua/strings/README.md) | trim, split/join, case conversion, padding, slugify, … plus [`width`](../lua/lib/lua/strings/width.lua): display-width (column) arithmetic — CJK/emoji/tab-aware `display_width`/`truncate`/padding ([`:help`](../doc/lib.nvim-strings_width.txt)) |
| `lib.lua.functions`| meta helpers: noop, identity, const, raise, …           |
| [`lib.lua.time`](../lua/lib/lua/time/diff/README.md) | time / diff calculation ([`:help`](../doc/lib.nvim-time_diff.txt)) |
| `lib.lua.json`     | decode helpers (string array)                           |
| [`lib.lua.memo`](../lua/lib/lua/memo/README.md) | memoization                          |
| [`lib.lua.lazy`](../lua/lib/lua/lazy/README.md) | lazy-`require` proxy                 |
| [`lib.lua.class`](../lua/lib/lua/class/README.md) | prototype OOP: `new`/`extend`/`include` mixins |
| [`lib.lua.context_manager`](../lua/lib/lua/context_manager/README.md) | try/finally: `with(acquire, release, body)` |

## `lib.nvim.*` — Neovim

| Module                 | Contents                                            |
| ---------------------- | --------------------------------------------------- |
| [`lib.nvim.notify`](../lua/lib/nvim/notify/README.md) | notify wrapper + log-level resolution |
| `lib.nvim.bindings.keymap`         | keymap helpers                                      |
| [`lib.nvim.count`](../lua/lib/nvim/count/README.md) | count-prefix helpers for keymaps: `get`/`raw`/`given`/`clamp`, plus `times` (sync repeat) and `chain` (async repeat gated on a completion signal) |
| [`lib.nvim.dotrepeat`](../lua/lib/nvim/dotrepeat/README.md) | wire a Lua function into native `.`-repeat via `operatorfunc`, no `vim-repeat` dependency |
| [`lib.nvim.lastcmd`](../lua/lib/nvim/lastcmd/README.md) | repeat the last *real* command — mapping or native change — skipping pure motions; nothing needs wrapping, since mappings are read off the key stream (`on_key` + `maparg`/`mapcheck`) and native changes are delegated to `.` via a `changedtick` comparison. Closes the gap that `.` cannot repeat Lua-callback mappings. Experimental: off, and binds no key, until `setup{ experimental = true }` (default trigger `<M-.>`) |
| [`lib.nvim.bindings.usercmd`](../lua/lib/nvim/bindings/usercmd/composer/README.md) | user-command helpers: `create` + [`composer`](../lua/lib/nvim/bindings/usercmd/composer/README.md) (subcommand verbs, completion, docgen — [`:help`](../doc/lib.nvim-composer.txt)) |
| `lib.nvim.bindings.autocmd`     | autocmd / augroup helpers                           |
| [`lib.nvim.bindings.audit`](../lua/lib/nvim/bindings/README.md) | keymap actions vs. command routes registered in the current session: `keymap_actions`/`command_routes`/`gaps`, `:LibBindingsAudit[Gaps] [path]` |
| `lib.nvim.buffer`      | buffer helpers (`insert_lines`, `is_markdown_buf`, `open_background`) |
| `lib.nvim.buf_win_tab` | buffer / window / tab utilities                     |
| [`lib.nvim.window`](../lua/lib/nvim/window/README.md) | overlay/float helpers: `make_scratch`, `open_named_scratch`, `open_scratch_split`, `tag` (find by `vim.w[win].custom_tag`), `nice_quit`, `set_title`, `close_on_focus_lost`, `center`, `attach` ([`:help`](../doc/lib.nvim-window.txt)) |
| [`lib.nvim.ui`](../lua/lib/nvim/ui/hover_select/README.md) | `hover_select` ([`:help`](../doc/lib.nvim-hover_select.txt)), [`statusline`](../lua/lib/nvim/ui/statusline/README.md) (per-window badge, float fallback under `laststatus=3`), highlight helpers |
| `lib.nvim.fs`          | path / filesystem helpers (`vim.fs` / `uv`): [`create_entry`](../lua/lib/nvim/fs/create_entry/README.md), [`mkdirp`](../lua/lib/nvim/fs/mkdirp/README.md) (fast-event-safe `mkdir -p`), [`normkey`](../lua/lib/nvim/fs/normkey/README.md), [`project_key`](../lua/lib/nvim/fs/project_key/README.md), `path_shorten` (fit/label styles), [`find_root`](../lua/lib/nvim/fs/find_root/README.md) (glob markers, optional chain cache, `skip_dirs`/`max_depth` bounds), [`chdir`](../lua/lib/nvim/fs/chdir/README.md) (explicit `cd`/`tcd`/`lcd` scope), [`dir_guard`](../lua/lib/nvim/fs/dir_guard/README.md) (hold the cwd against foreign changes), `relpath`, [`open.url.system_opener`](../lua/lib/nvim/fs/open/url/system_opener/README.md), [`collect_recursive`](../lua/lib/nvim/fs/collect_recursive/README.md) (`fs_scandir` walker + `collect_async`, a coroutine-driven non-blocking counterpart), [`scan_roots`](../lua/lib/nvim/fs/scan_roots/README.md) (multi-root scan + optional on-disk TTL cache, `scan_async` too), [`scan_cached`](../lua/lib/nvim/fs/scan_cached/README.md) (single-root scan + in-memory TTL cache, `scan_async` too) |
| [`lib.nvim.cross`](../lua/lib/nvim/cross/fs/separators/README.md) | cross-platform: OS detection, run/argv, [spawn env](../lua/lib/nvim/cross/run/env/README.md) (completed `PATH` + session/keyring vars), clipboard, uv (`spawn_capture` buffered, [`spawn_stream`](../lua/lib/nvim/cross/uv/spawn_stream/README.md) line-by-line), [path separators](../lua/lib/nvim/cross/fs/separators/README.md) (`unify_slashes`, `normalize`, `collapse_dots`, `has_win_sep`, `drive_upper`), [file mutation](../lua/lib/nvim/cross/fs/mutate/README.md) (retry on transient Windows sharing errors), [lock diagnosis](../lua/lib/nvim/cross/fs/lock/README.md) (which process holds a file open) |
| `lib.nvim.normalize`   | path / value normalization                          |
| `lib.nvim.git`         | git helpers                                         |
| `lib.nvim.terminal`    | terminal-buffer helpers                             |
| `lib.nvim.require`     | safe / dir / lazy require                           |
| `lib.nvim.lua_ls`      | LuaLS: module path, `@module` annotation            |
| `lib.nvim.core`        | misc Neovim helpers (`has_exec`, `simple_echo`)     |
| [`lib.nvim.deps`](../lua/lib/nvim/deps/README.md) | optional external tools (pandoc, ImageMagick, tesseract, …): `health` (`:checkhealth` reporting, replaces the hand-rolled `check_exe` pattern), `spec` (`docs/INSTALL.md`/`docs/install.json` parsing + lookup, `why` enforced), `pm` (package-manager detection + command composition), `install` (pure plan + confirmed terminal handoff), `view` (the report), and the `:Lib deps show|install` routes |
| `lib.nvim.neotree`     | neo-tree helpers: `node` (get_path / collect_nodes / extract_paths) |
| [`lib.nvim.treesitter`](../lua/lib/nvim/treesitter/guard/README.md) | `guard`: filetype allowlist gate for treesitter activation; [`parser_policy`](../lua/lib/nvim/treesitter/parser_policy/README.md): prompt-or-auto-install policy for missing-but-available parsers, persisted "never" list ([`:help`](../doc/lib.nvim-treesitter.txt)) |
| [`lib.nvim.system`](../lua/lib/nvim/system/README.md) | host env snapshot (`is_windows`/`is_wsl`/…, `home`, `pathsep`, `repo_base`) + Windows rpc pipe + `proc_trace` (blocking-call instrumentation for freeze diagnosis); opt-in `setup` |
| [`lib.nvim.progress`](../lua/lib/nvim/progress/README.md) | style-agnostic progress indicator: `notify`/`statusline`/`fidget`/`float`/`kit` renderers, delay-guard, focus-gated cancel-with-confirm ([`:help`](../doc/lib.nvim-progress.txt)) |
| [`lib.nvim.selection`](../lua/lib/nvim/selection/README.md) | reselect a Visual line/char range after a mapping mutates it: `keep_lines`/`keep_chars` ([`:help`](../doc/lib.nvim-selection.txt)) |
| [`lib.nvim.async`](../lua/lib/nvim/async/README.md) | coroutine async/await over libuv: `await`/`run`/`wrap`, plus `Semaphore` and `Condvar` — the shared core behind `fs.collect_recursive`'s async walk and `fs.write.async` ([`:help`](../doc/lib.nvim-async.txt)) |
| [`lib.nvim.harvest`](../lua/lib/nvim/harvest/README.md) | "collect from a scope, then show/export it" building blocks: `scope` (buffer/range/buffers/cwd/path → sources with provenance), `render` (rows → GFM table / CSV / lines), `sink` (clipboard / file / scratch buffer / picker), `emit` ([`:help`](../doc/lib.nvim-harvest.txt)) |
| [`lib.nvim.dev`](../lua/lib/nvim/dev/README.md) | tooling for developing *across* the ecosystem, not one plugin's runtime: `duplicates` — function bodies shared by two or more sibling repos, candidates for extraction into lib.nvim itself; `:LibDuplicateScan [path]` |

Opt-in call counting / usage statistics (`wrap`/`wrap_loaded`, persistence,
Markdown/browser reports, `:RATelemetry`) moved to
[`runtime-analysis.telemetry`](https://github.com/StefanBartl/runtime-analysis.nvim/blob/main/lua/runtime-analysis/telemetry/README.md)
— `docs/ECOSYSTEM.md` step 7 in that plugin's sibling, documentation.nvim.
This repo keeps a thin caller, `lib.strategies.telemetry_wrap`, for
instrumenting `require("lib")`'s own metatable-hidden aggregate specifically.

## Per-module documentation

Larger modules carry their own detailed docs. Markdown references sit next to
the source (good for browsing on GitHub); `:help` pages live in [`doc/`](../doc/)
and are generated on install by your plugin manager (see [Help docs](help.md)).

**Markdown references**

- [`lib.lua.memo`](../lua/lib/lua/memo/README.md) · [`lib.lua.lazy`](../lua/lib/lua/lazy/README.md) · [`lib.lua.time.diff`](../lua/lib/lua/time/diff/README.md)
- [`lib.nvim.notify`](../lua/lib/nvim/notify/README.md) · [`lib.nvim.window`](../lua/lib/nvim/window/README.md) · [`lib.nvim.ui.hover_select`](../lua/lib/nvim/ui/hover_select/README.md) · [`lib.nvim.ui.statusline`](../lua/lib/nvim/ui/statusline/README.md)
- [`lib.nvim.system`](../lua/lib/nvim/system/README.md) · [`lib.nvim.progress`](../lua/lib/nvim/progress/README.md) · [`lib.nvim.selection`](../lua/lib/nvim/selection/README.md)
- [`lib.nvim.buf_win_tab.capture`](../lua/lib/nvim/buf_win_tab/capture/README.md) · [`lib.nvim.buf_win_tab.resize_guarded`](../lua/lib/nvim/buf_win_tab/resize_guarded/README.md)
- [`lib.nvim.fs.ignore.list`](../lua/lib/nvim/fs/ignore/list/README.md) · [`lib.nvim.fs.is_subpath`](../lua/lib/nvim/fs/is_subpath/README.md) · [`lib.nvim.fs.polymorphic_rootresolver`](../lua/lib/nvim/fs/polymorphic_rootresolver/README.md) · [`lib.nvim.fs.find_root`](../lua/lib/nvim/fs/find_root/README.md)
- [`lib.nvim.fs.create_entry`](../lua/lib/nvim/fs/create_entry/README.md) · [`lib.nvim.fs.mkdirp`](../lua/lib/nvim/fs/mkdirp/README.md) · [`lib.nvim.fs.normkey`](../lua/lib/nvim/fs/normkey/README.md) · [`lib.nvim.fs.project_key`](../lua/lib/nvim/fs/project_key/README.md)
- [`lib.nvim.fs.chdir`](../lua/lib/nvim/fs/chdir/README.md) · [`lib.nvim.fs.dir_guard`](../lua/lib/nvim/fs/dir_guard/README.md)
- [`lib.nvim.fs.open.url.system_opener`](../lua/lib/nvim/fs/open/url/system_opener/README.md) · [`lib.nvim.cross.uv.spawn_stream`](../lua/lib/nvim/cross/uv/spawn_stream/README.md)
- [`lib.nvim.cross.fs.mutate`](../lua/lib/nvim/cross/fs/mutate/README.md) · [`lib.nvim.cross.fs.lock`](../lua/lib/nvim/cross/fs/lock/README.md)
- [`lib.nvim.cross.open_default`](../lua/lib/nvim/cross/open_default/README.md) · [`lib.nvim.cross.reveal_in_fm`](../lua/lib/nvim/cross/reveal_in_fm/README.md)
- [`lib.nvim.cross.run.env`](../lua/lib/nvim/cross/run/env/README.md) — spawn environment: completed `PATH` + session/keyring variables
- [`lib.nvim.lua_ls.insert.module_annotation`](../lua/lib/nvim/lua_ls/insert/module_annnotation/README.md)
- [`lib.nvim.treesitter.guard`](../lua/lib/nvim/treesitter/guard/README.md) · [`lib.nvim.treesitter.parser_policy`](../lua/lib/nvim/treesitter/parser_policy/README.md)
- [`lib.nvim.bindings.usercmd.composer`](../lua/lib/nvim/bindings/usercmd/composer/README.md)
- [`lib.nvim.deps`](../lua/lib/nvim/deps/README.md)
- [`lib.nvim.async`](../lua/lib/nvim/async/README.md) · [`lib.nvim.fs.watch`](../lua/lib/nvim/fs/watch/README.md) · [`lib.nvim.json`](../lua/lib/nvim/json/README.md)
- [`lib.nvim.dotrepeat`](../lua/lib/nvim/dotrepeat/README.md) · [`lib.nvim.lastcmd`](../lua/lib/nvim/lastcmd/README.md)
- [`lib.lua.class`](../lua/lib/lua/class/README.md) · [`lib.lua.context_manager`](../lua/lib/lua/context_manager/README.md)

**`:help` pages**

- `:help lib.nvim` — overview hub · `:help lib.nvim-modules` — module index
- `:help lib.nvim-window` · `:help lib.nvim-hover_select` · `:help lib.nvim-time_diff` · `:help lib.nvim-progress` · `:help lib.nvim-treesitter` · `:help lib.nvim-selection` · `:help lib.nvim-composer` · `:help lib.nvim-spawn-env` · `:help lib.nvim-async` · `:help lib.nvim-strings_width`

See [Conventions](conventions.md) for the steps to follow when documenting a new module, and [Help docs](help.md) for how `:help` tags are generated.
