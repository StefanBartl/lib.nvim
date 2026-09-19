# Namespaces & modules

For a function-signature-level index (every exported function, not just
namespace one-liners), split by topic, see [`API/README.md`](API/README.md).

This is a library, not a feature plugin: almost nothing here happens on its
own. It is the layer a plugin author requires so that the same problem is not
solved a fourth time in a fourth repository. Modules are requireable one by
one, so a plugin that needs one helper does not load the rest — the `lib`
aggregator exists for convenience, not as the entry point.

## Overview

| Namespace | Contains |
| --- | --- |
| `lib.lua.*` | Editor-independent Lua: tables, strings, numerals, time, JSON and YAML, classes, memoization, diffing, error handling, UUIDs |
| `lib.nvim.*` | Everything that needs `vim`: buffers, windows and tabs, filesystem, git, async and debounce, notifications, logging, treesitter, selections, terminals, caches, stores |
| `lib.nvim.ui` | The themed UI layer: the `kit` toolkit, list rendering, highlight helpers, nerd-font detection and statusline pieces — one look across sibling plugins instead of five |
| `lib.nvim.bindings` | Named keymap actions, and `usercmd.composer`: the subcommand-verb builder every sibling plugin's `:Command <sub>` grammar is built on |
| `lib.nvim.deps` | Declared optional external tools per plugin, and the popup, report and install command that go with them |
| `lib.strategies` | How the `lib` aggregator resolves: eager, lazy, metatable, with optional telemetry |

> **Compatibility, stated plainly.** This library tracks its author's own
> Neovim setup, and it stays in sync with *those* plugins by construction.
> Anyone else is welcome to use it, but the API is not held stable for external
> consumers and modules may be renamed or removed without a deprecation period.
> If you depend on it, pin a commit through your plugin manager's lockfile and
> upgrade deliberately.

## Detail, by namespace

## `lib.lua.*` — Lua

| Module             | Contents                                                |
| ------------------ | ------------------------------------------------------- |
| `lib.lua.tables`   | array / dict / set / functional / safe / unique / `with`|
| [`lib.lua.strings`](../lua/lib/lua/strings/README.md) | trim, split/join, case conversion, padding, slugify, … plus [`width`](../lua/lib/lua/strings/width.lua): display-width (column) arithmetic — CJK/emoji/tab-aware `display_width`/`truncate`/padding ([`:help`](../doc/lib.nvim-strings_width.txt)) |
| `lib.lua.functions`| meta helpers: noop, identity, const, raise, …           |
| [`lib.lua.time`](../lua/lib/lua/time/diff/README.md) | [`diff`](../lua/lib/lua/time/diff/README.md) (checkpoint timer, `:help`), [`format`](../lua/lib/lua/time/format/README.md) (`format_timestamp`: iso/human/short/log/filename), [`presets`](../lua/lib/lua/time/presets/README.md) (today/yesterday/last_week/this_month/this_quarter/this_year/custom ranges) ([`:help`](../doc/lib.nvim-time_diff.txt)) |
| [`lib.lua.json`](../lua/lib/lua/json/README.md) | `decode` (coerce an already-decoded JSON-shaped value to `string[]`, not a parser — see `vim.json.decode` for that) + `encode` (pure-Lua JSON encoder, callable + `.pretty`) |
| [`lib.lua.memo`](../lua/lib/lua/memo/README.md) | memoization                          |
| [`lib.lua.lazy`](../lua/lib/lua/lazy/README.md) | lazy-`require` proxy                 |
| [`lib.lua.class`](../lua/lib/lua/class/README.md) | prototype OOP: `new`/`extend`/`include` mixins |
| [`lib.lua.context_manager`](../lua/lib/lua/context_manager/README.md) | try/finally: `with(acquire, release, body)` |
| [`lib.lua.config`](../lua/lib/lua/config/README.md) | pure helpers for the "defaults + user overrides" config-store pattern: `deep_merge`, `get(tbl, path)` |
| [`lib.lua.diff`](../lua/lib/lua/diff/README.md) | line-array diff, two strategies: `lines` (cheap common-prefix/suffix splice region) and `myers` (full DP LCS-based edit script) |
| [`lib.lua.dump`](../lua/lib/lua/dump/README.md) | recursive Lua value dumper (tables/metatables/functions/threads/userdata), depth-limited against cyclic structures — `vim.inspect` alternative/complement |
| [`lib.lua.error`](../lua/lib/lua/error/README.md) | structured-error + safe-call-with-traceback convention: `new`, `is`, `safe_call` |
| [`lib.lua.numeral`](../lua/lib/lua/numeral/README.md) | numeral conversion: `roman` (1-3999) and `alpha` (bijective base-26, spreadsheet-column style) |
| [`lib.lua.uuid`](../lua/lib/lua/uuid/README.md) | UUIDv4 generation + formatting (not cryptographically secure — UI/temp-id use only) |
| [`lib.lua.yaml`](../lua/lib/lua/yaml/README.md) | deliberately minimal, dependency-free YAML-ish decoder (no anchors/aliases, no multi-document streams) |
| [`lib.lua.range`](../lua/lib/lua/range/README.md) | parse `"1-3,5,7"`-style range specs into a sorted, deduplicated `integer[]` — page/line/commit ranges |

## `lib.nvim.*` — Neovim

| Module                 | Contents                                            |
| ---------------------- | --------------------------------------------------- |
| [`lib.nvim.notify`](../lua/lib/nvim/notify/README.md) | notify wrapper + log-level resolution |
| `lib.nvim.bindings.keymap`         | keymap helpers                                      |
| [`lib.nvim.count`](../lua/lib/nvim/count/README.md) | count-prefix helpers for keymaps: `get`/`raw`/`given`/`clamp`, plus `times` (sync repeat) and `chain` (async repeat gated on a completion signal) |
| [`lib.nvim.dotrepeat`](../lua/lib/nvim/dotrepeat/README.md) | wire a Lua function into native `.`-repeat via `operatorfunc`, no `vim-repeat` dependency |
| [`lib.nvim.lastcmd`](../lua/lib/nvim/lastcmd/README.md) | repeat the last *real* command — mapping or native change — skipping pure motions; nothing needs wrapping, since mappings are read off the key stream (`on_key` + `maparg`/`mapcheck`) and native changes are delegated to `.` via a `changedtick` comparison. Closes the gap that `.` cannot repeat Lua-callback mappings. Experimental: off, and binds no key, until `setup{ experimental = true }` (default trigger `<M-.>`) |
| [`lib.nvim.bindings.keymap.modifier`](../lua/lib/nvim/bindings/keymap/modifier/README.md) | modifier keys that run *another* mapping and capture its result — `\[a` copies what `[a` produced, `\\[a` also inserts it. Resolves the following keys itself (buffer-local targets included) and recovers the result in tiers, the useful one needing no cooperation: diff the registers around the call. Experimental: binds nothing until `setup{ experimental = true }` |
| [`lib.nvim.bindings.usercmd`](../lua/lib/nvim/bindings/usercmd/composer/README.md) | user-command helpers: `create` + [`composer`](../lua/lib/nvim/bindings/usercmd/composer/README.md) (subcommand verbs, completion, docgen — [`:help`](../doc/lib.nvim-composer.txt)) |
| `lib.nvim.bindings.autocmd`     | autocmd / augroup helpers                           |
| [`lib.nvim.bindings.audit`](../lua/lib/nvim/bindings/README.md) | keymap actions vs. command routes registered in the current session: `keymap_actions`/`command_routes`/`gaps`, `:LibBindingsAudit[Gaps] [path]`; plus lints for key-portability (`key_risks`, `:LibBindingsAuditKeys`), vague route naming (`naming_candidates`, `:LibBindingsAuditNaming`), command-prefix collisions (`prefix_ambiguities`, `:LibBindingsAuditPrefixes`), and a generated manual-verification checklist (`checklist_lines`, `:LibBindingsAuditChecklist`) |
| [`lib.nvim.bindings.keymap.portability`](../lua/lib/nvim/bindings/README.md#keymapportabilitylua--auditkey_risks--can-the-terminal-send-it) | can a terminal actually deliver this `lhs`? A static classifier over the key notation — `portable` / `common` / `fragile` — because the runtime question has no answer: Neovim cannot press its own keys, and the "CSI u" query result reaches no Lua API |
| `lib.nvim.buffer.*`    | buffer helpers, each its own leaf module — `insert_lines`, `is_markdown_buf`, `open_background`, `get_alternate`, `context`, `apply_edits` (bottom-up positional text edits with an optional stale-match check per edit) (no `buffer/init.lua` aggregator; `require("lib.nvim.buffer")` alone does not resolve — require the leaf path, e.g. `lib.nvim.buffer.insert_lines`, or go through `require("lib")`, which flattens these directly) |
| `lib.nvim.buf_win_tab` | buffer / window / tab utilities: [`buffer_utils`/`windows_utils`/`tabs_utils`](../lua/lib/nvim/buf_win_tab/Command-List.md) (inspection/aggregation/reporting, no `init.lua` — required directly), [`get_option`](../lua/lib/nvim/buf_win_tab/get_option/README.md) (buffer option access across Neovim versions), [`normal_buffer`](../lua/lib/nvim/buf_win_tab/normal_buffer/README.md) (shared primitives around real file buffers), [`selection`](../lua/lib/nvim/buf_win_tab/selection/README.md) (read the visual selection whether or not visual mode is still active), [`word_under_cursor`](../lua/lib/nvim/buf_win_tab/word_under_cursor/README.md), [`safe_adjacent_buffer`](../lua/lib/nvim/buf_win_tab/safe_adjacent_buffer/README.md) (force-save the nearest normal buffer without touching the current one), [`move_buffer_to_tab`](../lua/lib/nvim/buf_win_tab/move_buffer_to_tab/README.md), [`resize_guarded`](../lua/lib/nvim/buf_win_tab/resize_guarded/README.md) (guarded window-resize keys, e.g. Shift+H/J/K/L, with terminal-buffer forwarding), [`capture`](../lua/lib/nvim/buf_win_tab/capture/README.md) (deterministic buffer/window capture after an Ex command) |
| [`lib.nvim.window`](../lua/lib/nvim/window/README.md) | overlay/float helpers: `make_scratch`, `open_named_scratch`, `open_scratch_split`, `tag` (find by `vim.w[win].custom_tag`), `nice_quit`, `set_title`, `close_on_focus_lost`, `center`, `attach`, `is_usable_window`/`target_window`, `ensure_bottom`/`make_focusable`/`force_focus`/`focus_and_bottom` (log/output-window focus helpers) ([`:help`](../doc/lib.nvim-window.txt)) |
| [`lib.nvim.ui`](../lua/lib/nvim/ui/kit/README.md) | [`kit`](../lua/lib/nvim/ui/kit/README.md) — select/chooser, prompts, confirm, compare (pick two, view side by side) ([`:help`](../doc/lib.nvim-kit.txt)), [`statusline`](../lua/lib/nvim/ui/statusline/README.md) (per-window badge, float fallback under `laststatus=3`), [`list`](../lua/lib/nvim/ui/list/README.md) (quickfix/loclist: entries + title + open/focus policy in one call), [`hl`](../lua/lib/nvim/ui/hl/README.md) (idempotent, optionally namespaced highlight-group definition, plus `persist()` for highlight state that survives a theme change), [`nerd_font`](../lua/lib/nvim/ui/nerd_font/README.md) (glyphs gated on a user declaration, never a font guess), [`icons`](../lua/lib/nvim/ui/icons/README.md) (file icons as data: glyph + colour + name per extension/file name/filetype, a curated devicons subset with the plugin asked first when it is loaded) |
| `lib.nvim.fs`          | path / filesystem helpers (`vim.fs` / `uv`): [`create_entry`](../lua/lib/nvim/fs/create_entry/README.md), [`mkdirp`](../lua/lib/nvim/fs/mkdirp/README.md) (fast-event-safe `mkdir -p`), [`normkey`](../lua/lib/nvim/fs/normkey/README.md), [`project_key`](../lua/lib/nvim/fs/project_key/README.md), [`path_shorten`](../lua/lib/nvim/fs/path_shorten/README.md) (fit/label styles), [`find_root`](../lua/lib/nvim/fs/find_root/README.md) (glob markers, optional chain cache, `skip_dirs`/`max_depth` bounds), [`chdir`](../lua/lib/nvim/fs/chdir/README.md) (explicit `cd`/`tcd`/`lcd` scope), [`dir_guard`](../lua/lib/nvim/fs/dir_guard/README.md) (hold the cwd against foreign changes), [`globbable`](../lua/lib/nvim/fs/globbable/README.md) (glob-safe path spelling — dodges the Windows 8.3-short-name-as-`~user` trap), [`watch`](../lua/lib/nvim/fs/watch/README.md) (debounced `fs_event` primitive), [`relpath`](../lua/lib/nvim/fs/relpath/README.md), [`collect_recursive`](../lua/lib/nvim/fs/collect_recursive/README.md) (`fs_scandir` walker + `collect_async`, a coroutine-driven non-blocking counterpart), [`scan_roots`](../lua/lib/nvim/fs/scan_roots/README.md) (multi-root scan + optional on-disk TTL cache, `scan_async` too), [`scan_cached`](../lua/lib/nvim/fs/scan_cached/README.md) (single-root scan + in-memory TTL cache, `scan_async` too) |
| [`lib.nvim.cross`](../lua/lib/nvim/cross/README.md) | cross-platform: OS detection, run/argv, [spawn env](../lua/lib/nvim/cross/run/env/README.md) (completed `PATH` + session/keyring vars), clipboard, uv (`spawn_capture` buffered, [`spawn_stream`](../lua/lib/nvim/cross/uv/spawn_stream/README.md) line-by-line), [path separators](../lua/lib/nvim/cross/fs/separators/README.md) (`unify_slashes`, `normalize`, `collapse_dots`, `has_win_sep`, `drive_upper`), [file mutation](../lua/lib/nvim/cross/fs/mutate/README.md) (retry on transient Windows sharing errors), [lock diagnosis](../lua/lib/nvim/cross/fs/lock/README.md) (which process holds a file open) |
| `lib.nvim.normalize`   | path / value normalization                          |
| `lib.nvim.git`         | git helpers                                         |
| `lib.nvim.terminal`    | terminal-buffer helpers                             |
| `lib.nvim.require`     | safe / dir / lazy require                           |
| `lib.nvim.lua_ls`      | LuaLS: module path, `@module` annotation            |
| `lib.nvim.core`        | misc Neovim helpers (`has_exec`, `simple_echo`)     |
| [`lib.nvim.deps`](../lua/lib/nvim/deps/README.md) | optional external tools (pandoc, ImageMagick, tesseract, …): `health` (`:checkhealth` reporting, replaces the hand-rolled `check_exe` pattern), `spec` (`docs/INSTALL.md`/`docs/install.json` parsing + lookup, `why` enforced), `detect` (is a tool here under any of the names it goes by -- `gs`/`gswin64c`), `pm` (package-manager detection + command composition), `install` (pure plan + confirmed terminal handoff), `view` (the report), `status` (every plugin's tools merged into one report), `require_tool` (the failure moment: the spec's `why` and this host's install command, at the point a command actually breaks), and the `:Lib deps show\|status\|install` routes |
| `lib.nvim.neotree`     | neo-tree helpers: `node` (get_path / collect_nodes / extract_paths) |
| [`lib.nvim.treesitter`](../lua/lib/nvim/treesitter/guard/README.md) | `guard`: filetype allowlist gate for treesitter activation; [`parser_policy`](../lua/lib/nvim/treesitter/parser_policy/README.md): prompt-or-auto-install policy for missing-but-available parsers, persisted "never" list ([`:help`](../doc/lib.nvim-treesitter.txt)) |
| [`lib.nvim.system`](../lua/lib/nvim/system/README.md) | host env snapshot (`is_windows`/`is_wsl`/…, `home`, `pathsep`, `repo_base`) + Windows rpc pipe + `proc_trace` (blocking-call instrumentation for freeze diagnosis) + `lines` (subprocess output chunks → whole lines: rejoins a line split across chunks, strips the CR `vim.system`'s `text = true` misses for a function handler) + `job` (`vim.system` with per-line callbacks); opt-in `setup` |
| [`lib.nvim.progress`](../lua/lib/nvim/progress/README.md) | style-agnostic progress indicator: `notify`/`statusline`/`fidget`/`float`/`kit` renderers, delay-guard, focus-gated cancel-with-confirm ([`:help`](../doc/lib.nvim-progress.txt)) |
| [`lib.nvim.frecency`](../lua/lib/nvim/frecency/README.md) | frequency x recency ranking for anything a user picks repeatedly: `store(namespace)` -> `record`/`score`/`lookup`, bucketed recency, log-dampened counts, persisted under `stdpath("data")`. One handle per namespace, because a store *is* its file |
| [`lib.nvim.image_preview`](../lua/lib/nvim/image_preview/README.md) | in-Neovim image preview via images.nvim / snacks.nvim / image.nvim (soft deps, auto-detected): `detect`/`available`/`preview(path)` into a floating window |
| [`lib.nvim.selection`](../lua/lib/nvim/selection/README.md) | reselect a Visual line/char range after a mapping mutates it: `keep_lines`/`keep_chars` ([`:help`](../doc/lib.nvim-selection.txt)) |
| [`lib.nvim.async`](../lua/lib/nvim/async/README.md) | coroutine async/await over libuv: `await`/`run`/`wrap`, plus `Semaphore`, `Condvar` and `LatestWins` (a "newest request wins" token gate for overlapping async work — picker previews, LSP requests, search-as-you-type) — the shared core behind `fs.collect_recursive`'s async walk and `fs.write.async` ([`:help`](../doc/lib.nvim-async.txt)) |
| [`lib.nvim.harvest`](../lua/lib/nvim/harvest/README.md) | "collect from a scope, then show/export it" building blocks: `scope` (buffer/range/buffers/cwd/path → sources with provenance), `render` (rows → GFM table / CSV / lines), `sink` (clipboard / file / scratch buffer / picker), `emit` ([`:help`](../doc/lib.nvim-harvest.txt)) |
| [`lib.nvim.dev`](../lua/lib/nvim/dev/README.md) | tooling for developing *across* the ecosystem, not one plugin's runtime: `duplicates` — function bodies shared by two or more sibling repos, candidates for extraction into lib.nvim itself; `:LibDuplicateScan [path]` |
| [`lib.nvim.vregex`](../lua/lib/nvim/vregex/README.md) | build `\V`-literal Vim-regex patterns from arbitrary text (`literal`/`escape`) — prevents regex-injection when user/arbitrary text is dropped into a search or `:s` pattern |
| [`lib.nvim.config.repo_file`](../lua/lib/nvim/config/repo_file/README.md) | Read a repository-local JSON config file and split its keys into an allowlist vs. everything else — the read/decode/split shape `documentation.nvim`'s and `lsp.nvim`'s project-config loaders each built independently before this existed. No path resolution, no warning text: both stay the caller's |
| [`lib.nvim.checkpoint`](../lua/lib/nvim/checkpoint/README.md) | snapshot a set of files before a destructive multi-file operation (`create`/`restore`/`discard`), byte-exact restore via `fs_copyfile`, built on `cross.fs.mutate` |

Opt-in call counting / usage statistics (`wrap`/`wrap_loaded`, persistence,
Markdown/browser reports, `:RATelemetry`) moved to
[`runtime-analysis.telemetry`](https://github.com/StefanBartl/runtime-analysis.nvim/blob/main/lua/runtime-analysis/telemetry/README.md)
— [`documentation.nvim/docs/ECOSYSTEM.md`](https://github.com/StefanBartl/documentation.nvim/blob/main/docs/ECOSYSTEM.md)
step 7, in that plugin's sibling.
This repo keeps a thin caller, `lib.strategies.telemetry_wrap`, for
instrumenting `require("lib")`'s own metatable-hidden aggregate specifically.

## Per-module documentation

Larger modules carry their own detailed docs. Markdown references sit next to
the source (good for browsing on GitHub); `:help` pages live in [`doc/`](../doc/)
and are generated on install by your plugin manager (see [Help docs](help.md)).

**Markdown references**

- [`lib.lua.memo`](../lua/lib/lua/memo/README.md) · [`lib.lua.lazy`](../lua/lib/lua/lazy/README.md) · [`lib.lua.time.diff`](../lua/lib/lua/time/diff/README.md)
- [`lib.nvim.notify`](../lua/lib/nvim/notify/README.md) · [`lib.nvim.window`](../lua/lib/nvim/window/README.md) · [`lib.nvim.ui.kit`](../lua/lib/nvim/ui/kit/README.md) · [`lib.nvim.ui.statusline`](../lua/lib/nvim/ui/statusline/README.md) · [`lib.nvim.ui.list`](../lua/lib/nvim/ui/list/README.md)
- [`lib.nvim.system`](../lua/lib/nvim/system/README.md) · [`lib.nvim.progress`](../lua/lib/nvim/progress/README.md) · [`lib.nvim.selection`](../lua/lib/nvim/selection/README.md)
- [`lib.nvim.buf_win_tab.capture`](../lua/lib/nvim/buf_win_tab/capture/README.md) · [`lib.nvim.buf_win_tab.resize_guarded`](../lua/lib/nvim/buf_win_tab/resize_guarded/README.md)
- [`lib.nvim.fs.ignore.list`](../lua/lib/nvim/fs/ignore/list/README.md) · [`lib.nvim.fs.is_subpath`](../lua/lib/nvim/fs/is_subpath/README.md) · [`lib.nvim.fs.stdpath_config_root`](../lua/lib/nvim/fs/stdpath_config_root/README.md) · [`lib.nvim.fs.polymorphic_rootresolver`](../lua/lib/nvim/fs/polymorphic_rootresolver/README.md) · [`lib.nvim.fs.find_root`](../lua/lib/nvim/fs/find_root/README.md)
- [`lib.nvim.fs.create_entry`](../lua/lib/nvim/fs/create_entry/README.md) · [`lib.nvim.fs.mkdirp`](../lua/lib/nvim/fs/mkdirp/README.md) · [`lib.nvim.fs.normkey`](../lua/lib/nvim/fs/normkey/README.md) · [`lib.nvim.fs.project_key`](../lua/lib/nvim/fs/project_key/README.md)
- [`lib.nvim.fs.chdir`](../lua/lib/nvim/fs/chdir/README.md) · [`lib.nvim.fs.dir_guard`](../lua/lib/nvim/fs/dir_guard/README.md) · [`lib.nvim.fs.globbable`](../lua/lib/nvim/fs/globbable/README.md)
- [`lib.nvim.cross.uv.spawn_stream`](../lua/lib/nvim/cross/uv/spawn_stream/README.md)
- [`lib.nvim.cross.fs.mutate`](../lua/lib/nvim/cross/fs/mutate/README.md) · [`lib.nvim.cross.fs.lock`](../lua/lib/nvim/cross/fs/lock/README.md)
- [`lib.nvim.cross.open_default`](../lua/lib/nvim/cross/open_default/README.md) · [`lib.nvim.cross.reveal_in_fm`](../lua/lib/nvim/cross/reveal_in_fm/README.md)
- [`lib.nvim.cross.run.env`](../lua/lib/nvim/cross/run/env/README.md) — spawn environment: completed `PATH` + session/keyring variables
- [`lib.nvim.lua_ls.insert.module_annnotation`](../lua/lib/nvim/lua_ls/insert/module_annnotation/README.md)
- [`lib.nvim.treesitter.guard`](../lua/lib/nvim/treesitter/guard/README.md) · [`lib.nvim.treesitter.parser_policy`](../lua/lib/nvim/treesitter/parser_policy/README.md)
- [`lib.nvim.bindings.usercmd.composer`](../lua/lib/nvim/bindings/usercmd/composer/README.md)
- [`lib.nvim.deps`](../lua/lib/nvim/deps/README.md)
- [`lib.nvim.async`](../lua/lib/nvim/async/README.md) · [`lib.nvim.fs.watch`](../lua/lib/nvim/fs/watch/README.md) · [`lib.nvim.json`](../lua/lib/nvim/json/README.md)
- [`lib.nvim.dotrepeat`](../lua/lib/nvim/dotrepeat/README.md) · [`lib.nvim.lastcmd`](../lua/lib/nvim/lastcmd/README.md)
- [`lib.nvim.image_preview`](../lua/lib/nvim/image_preview/README.md)
- [`lib.lua.class`](../lua/lib/lua/class/README.md) · [`lib.lua.context_manager`](../lua/lib/lua/context_manager/README.md)
- [`lib.lua.range`](../lua/lib/lua/range/README.md)
- [`lib.nvim.vregex`](../lua/lib/nvim/vregex/README.md) · [`lib.nvim.checkpoint`](../lua/lib/nvim/checkpoint/README.md)
- [`lib.nvim.config.repo_file`](../lua/lib/nvim/config/repo_file/README.md)

**`:help` pages**

- `:help lib.nvim` — overview hub · `:help lib.nvim-modules` — module index
- `:help lib.nvim-window` · `:help lib.nvim-kit` · `:help lib.nvim-time_diff` · `:help lib.nvim-progress` · `:help lib.nvim-treesitter` · `:help lib.nvim-selection` · `:help lib.nvim-composer` · `:help lib.nvim-spawn-env` · `:help lib.nvim-async` · `:help lib.nvim-strings_width`

See [Conventions](conventions.md) for the steps to follow when documenting a new module, and [Help docs](help.md) for how `:help` tags are generated.
