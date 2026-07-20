# nvim/templates

Copy-paste reference implementations for problems every `lib.nvim`-dependent
plugin's headless test suite runs into. Nothing under this directory is
`require`-able Lua module code (it does not live under `lua/`, on purpose —
see below) and none of it ships to consumers; it exists so the same few lines
don't get silently reinvented (and drift) across a dozen sibling repos.

## Why this can't just be a `lib.nvim` module

A plugin's headless test runner starts with `lib.nvim` absent from
`runtimepath` and `package.path` — that absence is exactly the problem
`resolve_lib_nvim.lua` solves. Anything that resolves it for you must itself
be reachable *before* that resolution happens, so it cannot be reached via
`require("lib.nvim...")`. Hence: a plain file to copy, not a module to
depend on.

## `resolve_lib_nvim.lua`

The `add_lib_nvim()` function: finds `lib.nvim` via `$LIB_NVIM_PATH` → sibling
checkout (`../lib.nvim`) → `stdpath("data")/lazy/lib.nvim`, and puts it on
both `runtimepath` and `package.path`. Copy the function itself into your
`docs/TESTS/run.lua` (or equivalent); then pick **one** of the caller
patterns below depending on how your plugin actually depends on `lib.nvim`.

### Pattern A — hard dependency, fail the whole suite

Use when the modules under test `require("lib.nvim...")` unconditionally, so
nothing can even load without it.

```lua
local lib_path = add_lib_nvim()
if not lib_path then
  print("FAIL  cannot locate lib.nvim (a runtime dependency of <plugin>).")
  print("      Set $LIB_NVIM_PATH, or check it out next to this repo.")
  os.exit(1)
end
```
Examples: `fileops.nvim`, `color_my_ascii.nvim`, `debugging.nvim`,
`diff.nvim`, `markdown.nvim` (all under `docs/TESTS/run.lua` or `TESTS/run.lua`).

### Pattern B — soft/optional dependency, note and continue

Use when the plugin bridges to `lib.nvim` via `pcall(require, ...)` with a
standalone fallback (so the suite is still meaningful without it — it just
exercises the fallback path instead of the bridged one).

```lua
if not add_lib_nvim() then
  print("note  lib.nvim not found — exercising the standalone fallback path.")
  print("      Set $LIB_NVIM_PATH or check it out next to this repo to test the bridge.")
end
```
Example: `buffer-ctx.nvim/docs/TESTS/run.lua`.

### Pattern C — resolve once, skip only the affected specs

Use when most of the suite is dependency-free and only a few spec blocks
touch `lib.nvim`-backed functionality; skip just those rather than the whole
run.

```lua
if not add_lib_nvim() then
  print("  skip <feature> tests (lib.nvim not on runtimepath)")
  return
end
```
Example: `pickers.nvim/docs/TESTS/pickers_spec.lua` (`command.complete`,
`sources.repos`, `selected_index.debounce` blocks).

### Pattern D — don't resolve at all, exclude from scope

Use when wiring up resolution isn't worth it for a given module — typically
because it also hard-requires something heavier than `lib.nvim` alone (e.g.
`telescope.nvim`), making a meaningful headless run impractical anyway. Just
leave the module's spec out of the runner's spec list, with a comment
explaining why, rather than trying to make it load.

Example: `migrate.nvim/docs/TESTS/run.lua` excludes `migrate.opt` /
`migrate.notify` / `migrate.common.*` (hard-require `lib.nvim` *and*
`telescope.nvim`) and only runs the dependency-free specs.

## Adding this to a new plugin

1. Copy `add_lib_nvim()` from `resolve_lib_nvim.lua` into your runner.
2. Pick A/B/C/D above based on how the plugin actually depends on `lib.nvim`.
3. Keep the env var name `$LIB_NVIM_PATH` — it's the one convention every
   existing copy agrees on (a couple of older copies used `$REPOS_DIR`
   instead; prefer `$LIB_NVIM_PATH` for new ones).
