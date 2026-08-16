# Tests

Headless spec suite for lib.nvim. Covers pure / buffer-level logic that is
testable without a UI.

## Run

From the repo root:

```sh
nvim --headless -u NONE -l docs/TESTS/run.lua
```

or:

```sh
nvim --headless -u NONE -c "set rtp+=." -c "luafile docs/TESTS/run.lua" -c "qa!"
```

The runner prints one line per spec and exits non-zero on the first failure
(`LIB_TESTS_OK` on success).

## Layout

| File              | Covers                                                          |
| ----------------- | --------------------------------------------------------------- |
| `harness.lua`     | Shared `eq`/`ok` assertions, `tmpfile()`, `read_lines()`.       |
| `logger_spec.lua` | `lib.nvim.logger`: records, level/tag/master switches, ring bound, redaction, guard/wrap, file sink (JSONL), flush/clear. |
| `lua_helpers_spec.lua` | `lib.lua.*`: `uuid`, `numeral` (roman/alpha), `diff` (lines/myers), `error` (structured errors, `safe_call`), `yaml`, `time` (presets/format), `strings` (utf8/encoding/distance/format/location/case/wrap + aggregator wiring), `tables.deep_merge`, `dump`, `class` (`new`/`init`/`extend`/override/fallthrough/`include` mixin composition), `context_manager.with` (release-on-success, multi-return + embedded-nil forwarding, release-on-body-error with the error surfacing, acquire-failure short-circuiting release/body entirely). |
| `nvim_helpers_spec.lua` | New `lib.nvim.*` adapters: module loading, aggregator wiring (`cross`/`window`), `core.first_available`, `normalize` validators, `cross.fs.expand_path`/`mutate`, `buf_win_tab.get_option`/`word_under_cursor`, and `fs` round-trips (`read`, `json`, `collect_recursive`, `scan_roots`). |
| `autocmd_dispatcher_spec.lua` | `lib.nvim.autocmd.dispatcher`: register/attach/detach/stats, sort-at-registration (priority + stable registration-order tiebreak), glob key matching, per-buffer `once` keyed independently per registration (regression: two registrations sharing one loader don't satisfy each other's `once`), key-list registrations, `opts.context` threading, and `dispatcher.filetype`'s real `FileType` dispatch + default buffer-context. |
| `context_spec.lua` | `lib.nvim.buffer.context` / `lib.nvim.window.context`: changedtick/same-event caching, hit/miss stats, `is_normal`/`has_filetype`/`is_processable`, lazy `.lines`, invalidation, invalid-handle fallback. |
| `cache_spec.lua`  | `lib.nvim.cache.disk`: save/load/clear/stats, TTL expiry. `lib.nvim.cache.memory`: namespaces, TTL eviction, changedtick-bound entries, invalidate/clear, and the opt-in/idempotent/toggleable `setup_auto_invalidation`/`disable_auto_invalidation`. |
| `cwd_spec.lua`    | `lib.nvim.fs.chdir` (scopes, normalization, rejection), `lib.nvim.fs.dir_guard` (revert/bypass/update/release, `on_violation`), and `find_root`'s `skip_dirs` / `max_depth` bounds on both the plain and chain-caching paths. |
| `statusline_spec.lua` | `lib.nvim.ui.statusline`: mode resolution against `laststatus`, both drawing strategies, `%` escaping, alignment, detach/restore. |
| `telemetry_wrap_spec.lua` | `lib.strategies.telemetry_wrap`: the one piece of telemetry testing that stays here after `runtime-analysis.telemetry` (moved from this repo, see `docs/modules.md`) took the rest — `setup()` enumerating `require("lib")`'s metatable-hidden aggregate (`control.keys()`) and installing real dispatchers over real lib.nvim functions, a real call counted through them, idempotent re-`setup()` (same instance, not a second live one), and `teardown()` restoring the aggregate byte-for-byte. Requires runtime-analysis.nvim on the runtime path (see `run.lua`'s `add_runtime_analysis()`). |
| `watch_spec.lua`  | `lib.nvim.fs.watch`: a real `fs_event` on a real temp directory — `on_change` fires after a real file write, rapid writes coalesce into fewer callbacks than writes (debounce), `stop()` is idempotent and prevents further callbacks. |
| `system_job_spec.lua` | `lib.nvim.system.job`: `start`'s line-buffering (terminated/unterminated/CRLF lines, stdout+stderr, no-output, optional callbacks). `start_blocking`: full stdout/exit-code captured synchronously on return, no extra `vim.wait` needed, `opts.stdin` reaching the process. `chain`: success path (one result per step), failure-gating (a failing middle step stops the chain), stdin auto-piped from the previous step's stdout, and an explicit `opts.stdin` overriding that default. |
| `git_spec.lua`    | `lib.nvim.git.info(dir)`: a real repo's branch/version/commit, a non-repo directory's all-nil fields, and a nonexistent directory not raising. The module's other ten cwd-reading functions predate this spec and are not covered here. |
| `deps_spec.lua`   | `lib.nvim.deps.spec`: `parse_markdown`/`parse_json` (well-formed, missing `bin`/`why`/`pkg`, `required` default, malformed input), `load`'s extension dispatch, `find`/`plugins` over both resolution sources — a fixture on `rtp`, and a fixture reachable *only* through a stubbed `lazy.core.config` (the not-yet-loaded case `runtimepath` cannot see). `deps.pm`: command composition against explicit manager definitions, incl. winget's one-command-per-package split. `deps.install`: `plan` classification and all three `run` refusal paths. `deps.view`: `lines` ordering (required-missing → missing → present), the short-`why` nudge, spec-error section. `deps.health`: `report`/`from_tools` smoke-tested not to error. |
| `spawn_env_spec.lua` | `lib.nvim.cross.run.env`: aggregator wiring (`cross.run.env`, `lib.spawn_env`), `SESSION_VARS` (wsl aliasing linux, common-first ordering, fresh list per call), `missing()` against `vim.env`, `candidate_dirs()` (only existing dirs, cached), `path()` (nothing inherited dropped, every candidate present, no duplicates under the Windows-insensitive rule, `extra_paths` order, `opts.base`), `build()` (exactly one PATH key whatever its casing, `vars` precedence, `passthrough`), `apply()` (unrelated options and a caller `env` survive, input not mutated), `login_shell_env()` (nil on native Windows), `clear()`. |
| `run_argv_spec.lua` | `lib.nvim.cross.run_argv`: `run_blocking`/`run_blocking_captured` against real commands (success, non-zero exit, the ENOENT regression that used to raise synchronously instead of returning `(false, err)`). |
| `run_spec.lua`    | `lib.nvim.cross.run`: `shell()` (native-Windows-vs-WSL `is_powershell`), `run`/`run_blocking` end to end, and the `cross.run.env` enrichment wired in by default — the completed `PATH` and an `opts.env` var actually reaching a real spawned subprocess (async and blocking), and `opts.env = false` genuinely skipping it rather than just skipping the override. |
| `async_walk_spec.lua` | The coroutine-driven `*_async` counterparts: `collect_recursive.collect_async`/`files_async`/`dirs_async` produce the exact same result set as their synchronous counterparts on a real fixture tree (including `ignore`-predicate pruning and a nonexistent-root settling to an empty list), `cancel()` genuinely suppresses `on_done`, and `scan_cached.scan_async`/`scan_roots.scan_async` carry the same TTL/cache-hit/refresh/multi-root semantics as their synchronous originals. |
| `run.lua`         | Runner: loads every spec, reports results, sets the exit code.  |

## Adding a spec

Create `<name>_spec.lua` returning `function(H) … end` (use `H.eq` / `H.ok` /
`H.tmpfile` / `H.read_lines`) and add its filename to the `specs` list in
`run.lua`.
