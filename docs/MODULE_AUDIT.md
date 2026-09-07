# Module audit (docs / @types / aggregator wiring / feature ideas)

Working checklist for a full pass over every top-level `lib.nvim.*` module
(granularity: the namespace tables in [modules.md](modules.md)). For each
module, verify against [conventions.md](conventions.md):

- [ ] `README.md` present and matches the actual exported API (no stale
      function names/signatures, no missing exports)
- [ ] `@types/` has proper `@class`/`@alias` defs (not inline in source),
      and the types match what the code actually returns/accepts
- [ ] Wired into [modules.md](modules.md): namespace table row +
      per-module-doc bullet (if it has a README)
- [ ] `doc/lib.nvim-<module>.txt` + hub line in `doc/lib.nvim.txt` (only for
      `:help`-worthy modules — not every module needs this)
- [ ] Feature idea check: "fehlt etwas Sinnvolles?" — noted below regardless
      of whether it gets built

Status legend: ⬜ not started · 🔎 in progress · ✅ audited (fixes applied or
nothing to fix) · 💡 has open feature idea(s) not yet acted on

Source-of-truth inventory (init/README/@types presence, `lua_files` = total
`.lua` count including submodules) taken 2026-09-07:

| Module | init.lua | README | @types | notes |
|---|---|---|---|---|
| async | Y | Y | 1 | |
| bindings | Y | Y | 0 (nested have own) | huge (34 files) |
| buf_win_tab | - (leaf-only) | - | 4 (nested) | documented exception? verify |
| buffer | - (leaf-only) | - | 1 (nested) | documented exception, see modules.md:34 |
| cache | Y | Y | 1 | |
| contextmenu | Y | Y | 1 | |
| core | Y | Y | 1 | |
| count | Y | Y | 1 | |
| cross | Y | Y | 5 (nested) | huge (42 files) |
| debounce | Y | Y | 1 | |
| deps | Y | Y | 1 | |
| dev | - (leaf-only) | Y | 0 | |
| dotrepeat | Y | Y | 1 | |
| frecency | Y | Y | 1 | |
| fs | - (leaf-only) | - | 5 (nested) | huge (52 files) |
| git | Y | Y | 1 | |
| harvest | Y | Y | 1 | |
| health | Y | Y | 1 | |
| image_preview | Y | - | 0 | no README at all |
| json | Y | Y | 1 | |
| lastcmd | Y | Y | 1 | |
| logger | Y | Y | 1 | |
| lua_ls | - (leaf-only) | - | 1 (nested) | |
| markdown | - (leaf-only) | - | 0 | |
| neotree | - (leaf-only) | - | 0 | |
| net | - (leaf-only) | - | 0 | |
| normalize | Y | Y | 4 (nested) | |
| notify | Y | Y | 1 | |
| progress | Y | Y | 1 | |
| require | Y | Y | 1 | |
| safe_api | Y | Y | 1 | |
| selection | Y | Y | 1 | |
| store | Y | Y | 1 | |
| system | Y | Y | 1 | |
| terminal | Y | Y | 1 | |
| token | Y | Y | 1 | |
| treesitter | - (leaf-only) | - | 0 | |
| ui | - (leaf-only) | - | 1 (nested) | huge (29 files) |
| window | Y | Y | 1 | |

Plus `lib.lua.*` namespace (tables, strings, functions, time, json, memo,
lazy, class, context_manager) — not yet inventoried, add before closing out.

## Per-module log

(One entry per module as it's actually reviewed — status, what was checked,
fixes made, feature ideas raised. Filled in as the sweep proceeds; this
section is the actual record, the table above is just the starting map.)

### core — ✅

- Found & fixed: [`lua/lib/nvim/init.lua`](../lua/lib/nvim/init.lua) docstring
  claimed `Nvim.map == require("lib.nvim.bindings.keymap")` — wrong, the
  `lib.nvim` aggregator is a straight 1:1 metatable; flattened short names
  only exist on `require("lib")` ([`lib/strategies/metatable.lua`](../lua/lib/strategies/metatable.lua)).
- Found & fixed: `core/@types/init.lua` had `@module 'lib.nvim.@types'`
  (should be `lib.nvim.core.@types`) and class `Lib.Nvim` (should be
  `Lib.Nvim.Core`, matching sibling naming `Lib.Nvim.Health`/`Lib.Nvim.Json`).
  Note: this surfaced a pre-existing, already-flagged issue in
  `lua/lib/@types/init.lua`'s `Lib.Modules` class (its own comment says it's
  stale/unreferenced, "left as-is pending an external-consumer check") — its
  `nvim Lib.Nvim` field now points at a genuinely undefined type instead of
  silently pointing at core's shape. Not touched; out of scope, already
  tracked by that file's own CDX comment.
- Feature idea: nothing obviously missing for this grab-bag module.

### async, contextmenu, count — ✅ no issues

Docs/@types are complete, accurate, and closely mirror the implementation.
Feature ideas (not implemented, just noted):
- `async`: a `sleep(ms)` convenience and `all(...)`/`race(...)` combinators
  (await N awaitables) would round this out as a small structured-concurrency
  kit, if a caller ever needs more than sequential awaits.
- `contextmenu`/`count`: no gap found.

### debounce — ✅ fixed

- `init.lua` and `buffer/init.lua` both did bare `return M`/`return { new =
  new }` with no `---@type` annotation (every sibling module annotates its
  return) — LuaLS gave no type info for `require("lib.nvim.debounce")` or
  `.debounce.buffer`. Also the module-surface classes themselves (`Lib.Debounce`,
  `Lib.Debounce.Buffer`) didn't exist yet, only their Handle/Opts sub-types.
  Added both classes and the `---@type` annotations.

### dotrepeat, git, json, lastcmd — ✅ (git fixed)

- `git/init.lua`: same missing-`---@type Lib.Git`-on-return bug as debounce,
  even though `Lib.Git` was already fully and correctly defined in `@types`.
  Fixed.
- dotrepeat/json/lastcmd: no issues. lastcmd in particular is exemplary —
  README documents even the sharp edges (the `repeat_last`-identity-comparison
  footgun it used to ship with).

### notify — ✅ fixed (undocumented submodule)

- `lib.nvim.notify.resolve_log_level` existed as a real, actively-used
  submodule (`lib.nvim.logger` depends on it) but was: not aggregated onto
  `require("lib.nvim.notify")` (only reachable at its own leaf path), absent
  from the README entirely, absent from `Lib.Notify`'s `@class` fields, and
  missing its own `---@type` return annotation. `modules.md`'s one-line
  description of `lib.nvim.notify` ("notify wrapper + log-level resolution")
  already promised this as part of the module's surface. Fixed all four.

### require, safe_api, selection — ✅ no issues

Docs/@types complete and accurate. No feature gaps found.

### store (+ store.project), terminal, token, health — ✅ (token fixed)

- `token/@types/init.lua` was missing the trailing `return {}` every other
  `@types` file in the repo has (harmless at runtime — nothing uses the
  require'd value — but inconsistent). Added.
- store/store.project, terminal, health: no issues, docs match code exactly.
- Feature idea: `lib.nvim.terminal` has no `is_terminal_buf`-style check for
  "is this a *specific* terminal job" (e.g. matching by `b:term_title` or
  job pid) — plausible future need if a caller wants to find/reuse a named
  terminal rather than just detect/delete one, but no concrete caller need
  identified, so just noted.

### harvest — ✅ fixed (biggest gap found so far)

- None of the 4 files (`init.lua`, `scope.lua`, `render.lua`, `sink.lua`) had
  a `---@type` annotation on their return, and — unlike every other
  multi-file module audited so far — **no module-surface classes existed at
  all** for `scope`/`render`/`sink`/the top aggregator itself; `@types` only
  had the data-shape classes (`Source`, `ScopeOpts`, `TableOpts`, ...). Added
  `Lib.Harvest.Scope`/`.Render`/`.Sink`/`Lib.Harvest` and all 4 return
  annotations. README itself was already accurate — this was purely a
  `@types` gap, LuaLS gave zero completion/checking on any harvest call
  before this.

### cache (+ disk, memory), deps (10 files), store — ✅ no issues

Both are exemplary: every submodule has a `---@type` return, every class is
complete and matches the code exactly, README covers 100% of the surface
including edge behavior (TTL clock choice, idempotency, etc.). No feature
gaps found.

### logger (8 files) — ✅ fixed (README gap) + 1 convention note

- `count`/`counters`/`add_sink` (all three fully and correctly typed in
  `@types`) and the top-level `loggers()` were entirely undocumented in the
  README — added a "Counters and extra sinks" section + a `loggers()`
  mention.
- Convention note, not fixed: `command.lua`/`config.lua`/`record.lua`/
  `ring.lua`/`serialize.lua`/`sinks.lua` are true internals (required only
  from within `logger/`, confirmed via repo-wide grep) but aren't named
  `_foo.lua`/under `internal/` per `conventions.md`, and have no `---@type`
  on their returns either. Correctly excluded from the public README either
  way. Left alone — renaming would touch require paths for no user-facing
  benefit; flagging here in case a future pass wants to formalize it.

### progress, cache, deps, store, normalize, system — ✅ no issues

`resolve_style.lua` and several `window/*.lua` files return a bare local
function rather than a table — not a bug: the function itself carries full
`---@param`/`---@return` annotations, so LuaLS types the returned value
correctly without a separate `---@type` (unlike the `return M`-table cases
elsewhere in this audit, where the table's shape isn't otherwise knowable).
`normalize` in particular is a good example of "exactly right": 21 functions,
21 README mentions, field counts in `@types` match exactly.

### window (15 files) — ✅ fixed (another orphaned submodule)

- `find_by_filetype.lua` — a real, complete, generically useful function
  (replaces filetree-manager-specific window lookups) — was not aggregated
  onto `window/init.lua`'s `M`, not in `@types`' `Lib.Window` class, not in
  the README's module-structure tree, and not in its "Functions" prose. Same
  shape as the `notify.resolve_log_level` gap from batch 1. Fixed all four.
- `tag.lua` had the same missing-`---@type`-on-`return M` issue as
  debounce/git (batch 1), even though `Lib.Window.Tag` already existed and
  was already correctly referenced from the top `Lib.Window` class — so this
  one only mattered for someone requiring `lib.nvim.window.tag` directly.
  Fixed.
- README's "Functions" section was also missing prose for four *already*
  aggregated-and-typed functions: `open_named_scratch`, `is_usable_window`/
  `target_window`, and the four focus helpers (`ensure_bottom`,
  `make_focusable`, `force_focus`, `focus_and_bottom`). Added all of it.

### dev, image_preview, lua_ls, markdown, neotree, net, treesitter — mostly ✅, 2 real fixes

These are the "leaf-only" namespaces (no top-level `init.lua`, per
`modules.md`'s documented exception pattern).

- **`dev/duplicates.lua`**: types were defined but inline in the source file
  rather than under `@types/` (violates `conventions.md`, though not
  functionally broken — left the existing `Hit`/`Group` classes where they
  were rather than relocating them, added the missing `Lib.Dev.Duplicates`
  module-surface class + `---@type` next to them for consistency with the
  rest of the audit).
- **`image_preview`** — biggest gap in the whole audit so far: a real,
  complete, 3-provider (images.nvim/snacks/image.nvim) module with **zero**
  of the three required doc layers (`conventions.md`'s checklist) — no
  README, no `@types` (its one alias was inline in `init.lua`, also a
  convention violation), not in `modules.md`'s namespace table, despite
  already having a one-line mention in `doc/lib.nvim.txt`'s hub (so it *was*
  known-about, just never finished). Wrote the README, added `@types/`,
  wired both bullets in `modules.md`.
- **`lua_ls.insert.module_annnotation`**: the directory/require-path itself
  has a typo (triple-n, `module_annnotation` not `module_annotation`) —
  already self-flagged in `lua_ls/@types/init.lua` by a prior CDX pass as a
  "phantom aggregate-module class" (no real `lua_ls/init.lua` aggregator
  exists), left alone since it's already correctly identified as known debt.
  What **wasn't** flagged: the submodule's own README had all four usage
  examples calling the *correctly-spelled, nonexistent* path
  (`module_annotation`) — copy-pasteable code that would `require`-error.
  Also two `notify.warn(...)` prefixes inside the module itself used the
  wrong spelling, and `modules.md`'s link text (not its href) showed the
  wrong spelling too. Fixed all three call sites to the real (typo'd) path;
  did not rename the directory itself (would be a breaking change for any
  external consumer already on the typo'd path — a rename-with-deprecation
  is a decision for the user, not an audit-sweep fix).
- **neotree.node, neotree.watch, net.curl**: same missing-`---@type`-on-
  `return M` pattern as debounce/git/tag (batches 1 & 3) despite fully
  correct module-surface classes already existing. Fixed all three.
- **neotree.watch README**: `installed()` and `clear()` — both real, typed
  functions — were undocumented. Added.
- **net.curl README**: `is_secret_header`/`config_quote` (public on purpose,
  per their own doc comment, "so a caller building its own argv shares
  this") were never named in the README's prose, only implied by the
  security section describing what they do. Added a one-line pointer.
- markdown.table, treesitter.guard, treesitter.parser_policy: no issues —
  every exported function accounted for in both README and `@types`.
