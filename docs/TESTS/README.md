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
| `run.lua`         | Runner: loads every spec, reports results, sets the exit code.  |

## Adding a spec

Create `<name>_spec.lua` returning `function(H) … end` (use `H.eq` / `H.ok` /
`H.tmpfile` / `H.read_lines`) and add its filename to the `specs` list in
`run.lua`.
