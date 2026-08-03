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
| `lua_helpers_spec.lua` | `lib.lua.*`: `uuid`, `numeral` (roman/alpha), `diff` (lines/myers), `error` (structured errors, `safe_call`), `yaml`, `time` (presets/format), `strings` (utf8/encoding/distance/format/location/case/wrap + aggregator wiring), `tables.deep_merge`. |
| `nvim_helpers_spec.lua` | New `lib.nvim.*` adapters: module loading, aggregator wiring (`cross`/`window`), `core.first_available`, `normalize` validators, `cross.fs.expand_path`/`mutate`, `buf_win_tab.get_option`/`word_under_cursor`, and `fs` round-trips (`read`, `json`, `collect_recursive`, `scan_roots`). |
| `context_spec.lua` | `lib.nvim.buffer.context` / `lib.nvim.window.context`: changedtick/same-event caching, hit/miss stats, `is_normal`/`has_filetype`/`is_processable`, lazy `.lines`, invalidation, invalid-handle fallback. |
| `cache_spec.lua`  | `lib.nvim.cache.disk`: save/load/clear/stats, TTL expiry. `lib.nvim.cache.memory`: namespaces, TTL eviction, changedtick-bound entries, invalidate/clear, and the opt-in/idempotent/toggleable `setup_auto_invalidation`/`disable_auto_invalidation`. |
| `cwd_spec.lua`    | `lib.nvim.fs.chdir` (scopes, normalization, rejection), `lib.nvim.fs.dir_guard` (revert/bypass/update/release, `on_violation`), and `find_root`'s `skip_dirs` / `max_depth` bounds on both the plain and chain-caching paths. |
| `statusline_spec.lua` | `lib.nvim.ui.statusline`: mode resolution against `laststatus`, both drawing strategies, `%` escaping, alignment, detach/restore. |
| `telemetry_wrap_spec.lua` | `lib.strategies.telemetry_wrap`: the one piece of telemetry testing that stays here after `runtime-analysis.telemetry` (moved from this repo, see `docs/modules.md`) took the rest — `control.keys()` enumerating `require("lib")`'s metatable-hidden aggregate, `wrap()`/`start()` installing real dispatchers over real lib.nvim functions, a real call counted through them, and `stop()` + `unwrap()` restoring the aggregate byte-for-byte. Requires runtime-analysis.nvim on the runtime path (see `run.lua`'s `add_runtime_analysis()`). |
| `git_spec.lua`    | `lib.nvim.git.info(dir)`: a real repo's branch/version/commit, a non-repo directory's all-nil fields, and a nonexistent directory not raising. The module's other ten cwd-reading functions predate this spec and are not covered here. |
| `run.lua`         | Runner: loads every spec, reports results, sets the exit code.  |

## Adding a spec

Create `<name>_spec.lua` returning `function(H) … end` (use `H.eq` / `H.ok` /
`H.tmpfile` / `H.read_lines`) and add its filename to the `specs` list in
`run.lua`.
