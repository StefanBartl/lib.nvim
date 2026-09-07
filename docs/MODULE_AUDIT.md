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
| bindings | Y | Y | 0 (nested have own) | huge (34 files) — ✅ audited 2026-09-07, see log |
| buf_win_tab | - (leaf-only) | - | 4 (nested) | documented exception, verified — ✅ audited 2026-09-07, see log |
| buffer | - (leaf-only) | - | 1 (nested) | documented exception, see modules.md:34 |
| cache | Y | Y | 1 | |
| contextmenu | Y | Y | 1 | |
| core | Y | Y | 1 | |
| count | Y | Y | 1 | |
| cross | Y | Y | 5 (nested) | huge (42 files) — ✅ audited 2026-09-07, see log |
| debounce | Y | Y | 1 | |
| deps | Y | Y | 1 | |
| dev | - (leaf-only) | Y | 0 | |
| dotrepeat | Y | Y | 1 | |
| frecency | Y | Y | 1 | |
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
| fs | - (leaf-only) | - | 5 (nested) | huge (52 files) — ✅ audited 2026-09-07, see log |
| ui | - (leaf-only) | - | 6 (nested) | huge (29 files) — ✅ audited 2026-09-07, see log |
| window | Y | Y | 1 | |

`lib.lua.*` namespace (16 top-level modules, 90 files, editor-independent
pure Lua — no `vim.*`), inventoried 2026-09-07:

| Module | init.lua | README | @types | notes |
|---|---|---|---|---|
| class | Y | Y | 1 | ✅ |
| config | Y | Y | 1 | ✅ was in neither `modules.md` nor `docs/API/foundations-lua.md` — fixed |
| context_manager | Y | Y | 1 | ✅ |
| diff | Y | Y | 1 | ✅ top-level, distinct from nested `time.diff` |
| dump | Y | Y | 1 | ✅ |
| error | Y | Y | 1 | ✅ |
| functions | Y | Y | 1 | ✅ |
| json | Y | Y | 1 | ✅ |
| lazy | Y | Y | 1 | ✅ |
| memo | Y | Y | 1 | ✅ |
| numeral | Y | Y | 1 | ✅ |
| strings | Y | Y | 6 (nested) | ✅ 21 files, see log — biggest structural fix of the audit |
| tables | Y | Y | 8 (nested) | ✅ 17 files, see log |
| time | - (leaf-only) | - | 1 (nested) | ✅ 12 files, 3 subdirs (diff/format/presets) |
| uuid | Y | Y | 1 | ✅ |
| yaml | Y | Y | 1 | ✅ |

## Per-module log

(One entry per module as it's actually reviewed — status, what was checked,
fixes made, feature ideas raised. Filled in as the sweep proceeds; this
section is the actual record, the table above is just the starting map.)

### Glue layer (`lib.config`, `lib.strategies.*`, `lib.@types.*`) — ✅ complete (2026-09-07)

**The `all_functions.lua` cross-check (the last open item) is done.** Method
was the one that found the `Lib.Strings`/`Lib.Tables` bug: every `---@field`
on the `Lib` class diffed against what `metatable.lua` (MODULE_MAP +
SPECIAL_HANDLERS), `eager.lua` and `lazy.lua` actually assign, then each
mismatch chased into the source. Six real findings, all fixed
(`lib.nvim@<pending>`), verified by `TESTS/run.lua` (all green) + a
three-strategy runtime smoke test:

- **`Lib.set` was typed `fun(group, opts, ns)` — a highlight setter** — but
  all three strategies export `lib.lua.tables.set` (the generic `Set<T>`
  module). Same actively-wrong-completions bug class as `Lib.Strings`:
  LuaLS suggested calling `lib.set("Group", {...})` and hid
  `lib.set.from_array`. Retyped to `Lib.Tables.Set`, moved up into the
  "Namespaces" block next to `array`/`core`/`dict`.
- **`Lib.safe` was typed `Lib.Notify.Safe`** — strategies export
  `lib.lua.tables.safe` (defensive nil-tolerant table mutators). Retyped to
  `Lib.Tables.Safe`, likewise moved into the "Namespaces" block. (Both
  `notify.safe` and `hl.set` stay reachable via `lib.notify` / `lib.hl`, so
  nothing is lost.)
- **`globbable` was a phantom field**: on the `Lib` class since `9265c34`
  (the commit that added the `fs.globbable` submodule) but wired into *no*
  strategy — under the default (metatable) strategy `lib.globbable(...)`
  raised `"lib: unknown key 'globbable'"`. Its direct siblings `mkdirp` /
  `path_shorten` / `relpath` were all exported everywhere. Wired into all
  three strategies (same remediation as `hex_to_string` last session).
- **`count_lines` missing from the `lazy` strategy** — on the `Lib` class,
  exported by metatable + eager, but the `lazy.lua` strings block skipped
  it, so `lib.count_lines(...)` was `nil` under that strategy. Added.
- **`json_decode_to_string_array` missing from `eager` + `lazy`** — on the
  base `Lib` class and exported by metatable, but the other two never
  provided that flat key. Added to both (points at the same
  `to_string_array.ensure_string_array` the class documents).
- **`eager.lua` called the key `autogroup` / `autogroup_create_clear`** —
  every other strategy and the `Lib.Strategy.Lazy` class use `augroup` /
  `augroup_create_clear`. A strategy swap would silently rename the key.
  Renamed in `eager.lua` to match.
- `lazy`'s extra keys (`augroup*`, `unique`/`unique_by`/`is_unique`,
  `json_is_array_like` & siblings) now match the `Lib.Strategy.Lazy` class
  *exactly*. `eager`'s extras (`augroup*` plus a raw `json` module handle)
  are documented in a header comment in `eager.lua` as deliberate,
  non-common-surface extras kept to avoid a breaking removal.
- **`docs/configuration.md`** claimed "All strategies expose the same
  surface" — directly contradicted by the `Lib.Strategy.Lazy` class (which
  exists precisely because `lazy`/`eager` add keys the default strategy
  does not). Softened to: every strategy provides the full `Lib` surface,
  and `lazy`/`eager` add a few flattened conveniences on top.
- `lib/@types/luassert.lua` (85 lines): reviewed — exceptionally
  self-documented (explains the busted-wiring failure it repairs, why not
  `runtime.path`, the two widened signatures), internally consistent, the
  `luassert.internal` reopen lists exactly the assertions these repos call
  with a message. Nothing to fix.
- `lib/@types/init.lua`'s `Lib.Modules` class: left untouched — already
  self-flagged (CDX comment) as stale/unreferenced "pending an
  external-consumer check", same precedent as every other self-flagged
  debt item in this audit.

**This completes the entire `lib.nvim` module audit.** See the closing note
at the end of this file.

---

<details>
<summary>Original partial-progress note from the previous session (kept for history)</summary>

#### 🔎 partial (session ended low on budget)

- `lib.config` (setup/get/strategy_module), `lib.strategies.control`
  (register/active/keys/reset_cache), `lib.strategies.telemetry_wrap`
  (setup/teardown): none had a module-surface class despite complete real
  functions — same mechanical pattern as the rest of this audit. Added and
  wired all three, `lib.nvim@e77c981`.
- `lib.strategies.{eager,lazy,metatable}` (the three actual aggregator
  strategies): already had correct `---@type Lib`/`Lib.Strategy.Lazy` on
  their `return`. No fix needed.
- `lib/health.lua`: single `M.check()`, the native Neovim `:checkhealth`
  contract — not a library-API surface, doesn't need a module class.
- `lib/@types/misc.lua` (21 lines, shared cross-cutting types: `OsShell`,
  `OsRunResult`, `Lib.Cross.Platform.PlatformName`): spot-checked, no
  issues.
- **NOT done, flagged for next session**: a full field-by-field cross-check
  of `lib/@types/all_functions.lua`'s `Lib` class (129 lines, ~100+
  fields, "KEEP IN SYNC with... lib/strategies/metatable.lua") against
  what `eager.lua`/`lazy.lua`/`metatable.lua` actually assign — the same
  method that found the `Lib.Strings`/`Lib.Tables` bug (`grep -oE
  "^LIB\.[a-zA-Z_0-9]+" lua/lib/strategies/eager.lua` vs. the class's
  `@field` list). Not attempted this session due to a hard budget cutoff
  (~6% usage remaining) — this file is NOT self-flagged as stale like
  `Lib.Modules` is, so there's no known reason to suspect it's wrong, but
  it also was never verified the way strings/tables were.
- `lib/@types/init.lua`'s `Lib.Modules` class: already self-flagged via
  CDX comment as stale/unreferenced, "pending an external-consumer check"
  — left untouched, consistent with every other self-flagged debt item
  found throughout this whole audit (same reasoning as `Lib.Fs`/
  `Lib.Cross.ALL`/`buf_win_tab`'s `Lib.BufWinTab`).
- `lib/@types/luassert.lua` (85 lines): not reviewed this session (test-
  framework types, lower priority, budget ran out first).

**If resuming**: this is the only unfinished item in the entire
`lib.nvim` module audit. Everything else (20 small/medium modules, all
five huge subsystems, the complete `lib.lua.*` namespace, and the rest of
this glue layer) is done.

</details>

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

### ui (kit, list, statusline, hl, nerd_font — 29 files) — ✅ reduced-depth pass, 2 fixes

First of the five huge subsystems. Depth reduced per the handover's own
lever: top-level README/`@types`/`modules.md` wiring checked for every leaf,
full function-by-function README diff only where something looked off
(not for every one of `kit`'s 20 files individually).

- **`nerd_font` — same "vergessenes Submodul" shape as `image_preview`/
  `notify.resolve_log_level`/`window.find_by_filetype`**: a real, complete,
  actively-used (by `bindings.keymap.which_key`) 4-function module
  (`available`/`glyph`/`chars`/`sep`) with **zero** of the three doc layers
  — no README, no `@types` (its `return M` had no `---@type` either), and
  not in `modules.md`'s `ui` row at all. Wrote the README, added `@types/`,
  added the `---@type` annotation, wired into `modules.md`.
- **`kit.compare`** — a whole, fully-implemented feature (pick two items
  from one picker, view side by side; three-state SEARCH→MARKED→COMPARE
  flow, its own `CompareOpts`/`CompareHandle` types, dispatchable via
  `kit.popup({type="compare"})`) had **zero** README coverage — not in the
  components table, no dedicated section, unlike every sibling component
  (`note`/`viewer`/`toast`/.../`menu`). `kit.chooser` (the low-level escape
  hatch `select`/`compare` share) was in the same spot — self-documented
  only in its own doc comment. Added a components-table row + a full
  "Compare" section (mirroring the existing "Interactive picker"/
  "Button-confirm" sections) covering both.
- **`list/init.lua`**: same missing-`---@type Lib.UI.List`-on-`return M`
  bug as the ~6 other modules this pattern has turned up in this audit,
  despite `Lib.UI.List` already being fully and correctly defined. Fixed.
- **`modules.md`'s `ui` row**: `hl` was described only as generic prose
  ("highlight helpers"), not linked, despite having a complete README —
  now linked like every sibling.
- **`ui/@types/init.lua`'s `Lib.UI` "phantom aggregate" class**: already
  self-flagged by a prior CDX pass as incomplete/possibly-stale (`ui/` has
  no `init.lua`, so nothing actually returns this shape) — same pattern as
  `core`'s `Lib.Modules` finding and `buffer/@types`'s own note, all three
  explicitly "pending an external-consumer check" before deciding
  delete-vs-complete. Left untouched, same reasoning as those two: adding
  the two fields it's missing (`statusline`, `nerd_font`) would be
  premature work on a class that might get deleted outright.
- `list`, `statusline`, `hl`: README/`@types` otherwise complete and
  accurate (spot-checked function-by-function, not just presence).
- Feature idea: none obviously missing in any of the five leaf modules —
  `kit` in particular already covers the space thoroughly (12 component
  types, a layout engine, sync bridge for blocking call sites).

### fs (29 leaf submodules, 52 files) — ✅ reduced-depth pass, several fixes

Second of the five huge subsystems. Same reduced-depth method as `ui`: for
every one of the 29 leaf modules, checked README/`@types`/wiring presence;
full function-by-function README diff done for all of them (delegated half
to a sub-agent for the mechanical spot-check, verified its findings myself
before acting), not just presence.

Discovered along the way: `docs/API/*.md` (`filesystem.md` + 4 sibling
files, one per big subsystem) is a whole parallel, more detailed doc layer
this audit's methodology hadn't accounted for — `modules.md`'s per-module
row is deliberately just a terse one-liner that hands off to it
(`docs/API/README.md` says so explicitly). This means an item missing from
`modules.md`'s row-38 fs sentence is *not* automatically a bug the way an
item missing from a small module's one-and-only README would be — checked
`docs/API/filesystem.md` for completeness instead, which is the real
per-function reference for this subsystem.

- **`fs.path` (`from_repo_relative`/`joinpath`/`ensure_dir`) had no module-
  surface class at all** — same "harvest" shape as batch 5: three real,
  typed-per-function methods, `return M` with no `---@type`. Added
  `Lib.Fs.Path` to `path/@types/init.lua` + the `---@type` annotation. This
  collided with an already-self-flagged **fictional** `Lib.Fs.Path` of the
  same name in `fs/@types/path.lua` (part of the stale `Lib.Fs`/`Lib.Fs.ALL`
  grouping every prior batch has left alone) — since mine is now the real,
  referenced one, gutted the duplicate in `fs/@types/path.lua` down to a
  pointer comment rather than leaving two class bodies with the same name.
- **`fs.ignore.list`**: same missing-module-class pattern (5 functions + 2
  data fields, zero `@types`) — added `Lib.Fs.Ignore.List`. Its README also
  had 4 of 5 functions in the Public API section but not `normalize()`
  (the one every `as_*` adapter calls internally) — added.
- **`fs.relpath` — a doc-drift regression, not a gap**: has a real, complete
  README, but `docs/API/filesystem.md` said "(no README)" for it and
  `modules.md`'s row-38 sentence had it as unlinked plain text (same for
  `path_shorten`, also unlinked despite a real README) — the README was
  added after both of those were written and neither got updated. Fixed
  both links + the API-doc annotation.
- **`fs.polymorphic_rootresolver` — 3 doc-vs-code drifts**, all now fixed:
  (1) `cfg.resolve` (a real, used override for the whole marker search,
  already correctly typed in `@types`) was entirely absent from the
  README's Configuration section; (2) the sibling
  `example-setup-luals-marksman.md` required a wrong module path throughout
  (`polymorphic_root_resolver`, extra underscore) and called it as
  `resolver_module.make_root_dir_resolver(...)` as if `require` returned a
  table — it returns the factory function directly, so every example in
  that file would `require`-error or call-error if copy-pasted; (3) the
  README's flow diagram depicted two sequential built-in marker-check
  stages (VCS then project-config) — code does one `vim.fs.root` call with
  whatever combined marker list the caller passes, so the diagram implied
  functionality that doesn't exist. Corrected all three.
- **`docs/API/filesystem.md` + `docs/API/README.md` both said "26
  submodules"** for fs — actual count (headings in `filesystem.md`, which
  matches the real README count exactly) is 29. Fixed both.
- Remaining 25 of 29 leaf modules (`chdir`, `dir_guard`, `find_root`,
  `find_upward_dir`, `create_entry`, `mkdirp`, `json`, `trash`, `watch`,
  `scan_roots`, `scan_cached`, `collect_recursive`, `write.{to_file,append,
  async,batch}`, `read`, `normkey`, `project_key`, `globbable`, `is_dir`,
  `is_readable_file`, `is_subpath`, `is_valid_filename`): no discrepancies
  — READMEs match code exactly, `@types` (where present) match, and the
  ~13 modules with no `@types` dir all legitimately return a bare
  `function(...)` fully self-typed via its own `---@param`/`---@return`
  (the established non-bug pattern from earlier batches), not a gap.
- Feature idea: none obviously missing — `fs` already covers path
  resolution, root detection, stat checks, directory creation/scanning
  (sync + async variants throughout), ignore lists, read/write/watch, and
  trash, each with a clear single-responsibility module.

### cross (~28 leaf modules across platform/executable/fs/run/uv, 42 files) — ✅ reduced-depth pass, several fixes

Third of the five huge subsystems. Same method as `ui`/`fs`, half delegated
to a sub-agent (verified every finding myself before acting, same as the
`fs` batch).

- **`cross/init.lua` — the root aggregator itself, the single most-used
  require in the whole subsystem — had no `---@type Lib.Cross` on its
  `return M`**, despite `Lib.Cross` being fully and correctly defined.
  Unlike `fs`/`ui`/`buffer` (leaf-only, no real aggregate to type), `cross`
  has a genuine working `init.lua` aggregator, which makes this the
  highest-impact single fix in the whole audit so far. Fixed.
- **`modules.md`'s `lib.nvim.cross` row-header link pointed at the wrong
  file** — `fs/separators/README.md` (a leaf three levels down) instead of
  `cross/README.md` (the real, substantial root README). Fixed.
- **`cross.executable` had no module-surface class at all** (same
  "harvest"/`fs.path` shape): `exists`/`path`/`find`/`mason_bin`/`clear`,
  zero `@types`. The top-level `Lib.Cross` class even already had a prose
  comment on its generic `executable table` field naming `clear` — so the
  gap was known-about, just never finished. Added `Lib.Cross.Executable` +
  wired it into `Lib.Cross.executable`. `clear(name?)` was also entirely
  undocumented in the module's own README (real, used for cache
  invalidation after installing a tool mid-session) — added.
- **`cross.run_argv.run_async_captured`** — a real, complete, substantially
  commented async function (non-blocking counterpart to
  `run_blocking_captured`, explicitly written to fix "the biggest source of
  UI freezes across the plugins built on this library") — existed and was
  correctly typed in `@types`, but was in neither the module's own README
  nor `docs/API/cross-platform.md`. Same "vergessenes Submodul" shape as
  `ui.nerd_font`/`fs.path`. Added to both.
- **`cross.fs.mutate`**: missing `---@type` on `return M` (mechanical
  pattern, ~10th time this audit has found it) despite a fully correct
  `Lib.Cross.Fs.Mutate` class; that class's own file was also missing the
  trailing `return {}` every sibling `@types` file has (harmless, but
  inconsistent — same class of nit as `token`'s fix in batch 2). Both
  fixed. Separately, `docs/API/cross-platform.md`'s mutate section was
  missing `symlink`/`hardlink` entirely (real, in the module's own README
  and `@types` already) — added.
- **`cross.run.env`**: missing `---@type` on `return M` despite a fully
  correct `Lib.Cross.Run.Env` class (same mechanical pattern). Separately,
  `M.array()` (converts `build()`'s dict-shaped env to the array shape raw
  `uv.spawn` — and this module's own sibling `cross.uv.spawn_capture` —
  wants) was documented in the module's own README and `@types` but absent
  from `docs/API/cross-platform.md`'s function list. Both fixed.
- **`cross.uv.spawn_capture`**: `opts.stdin` (real, used to hand a
  credential to a child via its stdin instead of argv, where any process on
  the machine could read the command line) was correctly typed in `@types`
  but undocumented in both the module's own README and
  `docs/API/cross-platform.md`. Added to both.
- **`cross.run` (the leaf module, not the assembled `cross.run` aggregate
  sub-table)**: verified its `return M` deliberately has *no* `---@type`
  annotation, and confirmed that's correct rather than a gap — the existing
  `Lib.Cross.Run` class describes the aggregate shape (adds `run_argv`/
  `env`, assembled later in `cross/init.lua`), so annotating this leaf's
  own 4-field table with that class would be a type error, not a fix.
- Everything else checked (platform.is_{wsl,macos,linux}, copy_to_clipboard,
  fs._cwd/expand_path/lock/wslpath, fs.separators.*, open_default,
  reveal_in_fm, uv.fs/spawn_command/spawn_shell_command/spawn_stream/
  wait_until): no discrepancies.
- Feature idea: none obviously missing — `cross` already covers OS
  detection, three tiers of process spawning (shell-string/argv/libuv-
  direct, each with blocking+async variants), path separators, file
  mutation with Windows-sharing-error retry, and lock diagnosis.

### bindings (keymap/autocmd/usercmd + composer/dispatcher/modifier/portability/audit, 34 files) — ✅ reduced-depth pass, several fixes

Fourth of the five huge subsystems. `bindings/init.lua` and each of
`keymap`/`autocmd`/`usercmd`/`composer`/`dispatcher`/`modifier` already had
correct `---@type` on their aggregator `return`s (unlike `cross`, no
mechanical gap here at the top level) — this subsystem was clearly kept in
good shape already. `composer` — "the most widely-used component of the
library, 30+ consuming plugins" — got a dedicated deep pass (delegated to a
sub-agent tracing every behavioral claim in its 405-line README against
`argtypes`/`check`/`complete`/`docgen`/`flags`/`kv`/`parse`/`registry`/
`tree`): **entirely clean**, not one discrepancy found. Good sign for the
overall quality of this subsystem's docs.

- **`keymap.portability`** (a real, actively-used, 2-function module —
  `classify`/`is_portable`, used by `bindings.audit.key_risks`) had no
  module-surface class, and its `Tier` alias was defined inline in the
  source rather than under `@types/` (violates `conventions.md`, same
  pattern as `dev.duplicates` from an earlier batch). Added
  `keymap/@types/portability.lua` with both, plus the `---@type`
  annotation.
- **`cross.executable`-shaped gap, twice more**: `autocmd.docs` (4
  functions: `write`/`check`/`write_all`/`create_usercmd`) and
  `bindings.audit` (14 functions) both had their real classes/`---@type`
  missing or partial. `autocmd.docs`'s three classes (`Opts`/`AllOpts`/
  `AllResult`) were inline in `docs.lua` instead of under `@types/`
  (convention violation) — moved to a new `autocmd/@types/docs.lua`.
  `bindings.audit`'s five classes were inline in `audit.lua` itself, same
  fix, into a new `bindings/@types/audit.lua`. `usercmd.docs` already had
  a correct class (`Lib.UserCommand.Docs`) sitting unused — just needed
  the `---@type` on its `return M`.
- **`autocmd.docs.write_all()` — a whole real, substantial feature
  (multi-repo batch doc-writing, with a full paragraph of design rationale
  in its own doc comment) — was completely absent from `autocmd/README.md`**.
  Same "vergessenes Feature" shape as `run_async_captured` (cross batch)
  and `kit.compare` (ui batch). Added a full section.
- **`bindings.audit` had three whole undocumented lint features**:
  `naming_candidates`/`naming_candidate_lines` (vague command-route-naming
  lint), `prefix_ambiguities`/`prefix_ambiguity_lines` (`<Tab>`-completion
  collision lint), `checklist_lines` (generated manual-verification
  Markdown checklist) — none mentioned anywhere in `bindings/README.md`,
  despite `create_usercmd()` actually registering six commands for them
  (`:LibBindingsAudit[Gaps|Keys|Naming|Checklist]` + `...Prefixes`) while
  the README's prose only described three. Added all three feature
  sections + corrected the command list. Also extended `modules.md`'s
  one-line `bindings.audit` summary to name all four lints, not just one.
- **`docs/API/commands-and-infra.md` had four real gaps**, all now fixed:
  `lib.nvim.bindings.keymap.modifier` and `.keymap.portability` were
  entirely absent (both have real READMEs); the `autocmd` section's
  function list was missing `registered`/`by_event`/`delete`/`docs`
  entirely (only `augroup`/`group`/`get_augroup`/`create`/
  `norm_events`/`norm_pattern` were listed) and had no `autocmd.docs`
  subsection at all; the `usercmd` section was likewise missing
  `registered`/`delete`/`docs`; `lib.nvim.bindings.audit` itself was
  absent. Added all four.
- Everything else checked (`keymap`'s own README/init.lua/registry
  internals, `autocmd`'s three-augroup-mechanisms design — already
  self-documented in its own README as deliberate — `autocmd.dispatcher`,
  `usercmd`'s own surface, `docs_util.lua` — confirmed genuinely internal,
  used only within `bindings/` itself, correctly excluded from the public
  README like `logger`'s internals in an earlier batch): no further
  discrepancies.
- Feature idea: none obviously missing — this subsystem already covers
  keymaps (one-off + named-action registry + reachability lint + result-
  capturing modifier), autocmds (registry + augroup dedup + a full
  priority-ordered lazy dispatcher), user commands (registry + the
  composer subcommand DSL), and a cross-cutting audit tool tying the first
  two together with four separate lints.

### buf_win_tab (buffer_utils/windows_utils/tabs_utils + capture/get_option/move_buffer_to_tab/normal_buffer/resize_guarded/safe_adjacent_buffer/selection/word_under_cursor, 23 files) — ✅ reduced-depth pass, minor fixes

Fifth and last of the five huge subsystems — also by far the smallest and
cleanest one. Leaf-only namespace confirmed (no `buf_win_tab/init.lua`),
same self-flagged fictional-aggregator pattern as `Lib.Modules`/`Lib.Fs`/
`Lib.Cross` (`Lib.BufWinTab`/`Lib.BufWinTab.All` in `@types/init.lua`), left
untouched per established precedent. `docs/API/ui-windows-buffers.md`
(the parallel deep-doc file, per the lesson from `fs`/`cross`/`bindings`)
was already fully accurate and complete for all 11 pieces of this
subsystem — nothing to fix there, a good sign.

- **`windows_utils.collect_win_report()`** (a real, substantial window-
  inspection function, already correctly typed in `@types` and already
  correctly listed in `docs/API/ui-windows-buffers.md`) was missing from
  `Command-List.md` — the `README.md`-equivalent this subsystem's three
  loose top-level files (`buffer_utils`/`windows_utils`/`tabs_utils`, no
  `init.lua` of their own) use instead of individual READMEs. Added, plus
  fixed an adjacent pre-existing broken Markdown table row (an unescaped
  `|` inside `string|nil` had split one row into a phantom extra column).
- **`modules.md`'s `buf_win_tab` row had zero links** ("buffer / window /
  tab utilities", nothing else) despite all 8 leaf submodules plus
  `Command-List.md` being fully documented — every other subsystem's row
  links out. Rewrote it to link all 8.
- **`resize_guarded/README.md`'s "File location" section pointed at a
  stale, wrong path** (`lua/lib/buf_win_tab/resize_guarded.lua` — missing
  the `nvim` segment, and not even the real file: the module is
  `resize_guarded/init.lua`, not a flat file). Fixed.
- Two lower-confidence sub-agent findings (`get_option`/`word_under_cursor`
  each have an unused, exactly-matching `@types` alias sitting next to a
  `return function(...)` that's already fully self-typed via its own
  `---@param`/`---@return`) were **not** treated as bugs — same established
  non-fix precedent as `resolve_style.lua`/`is_dir` from earlier batches:
  LuaLS types the return identically either way, so linking the unused
  alias would be pure tidiness with no functional benefit, not a
  documentation or type-safety gap.
- Everything else (`capture`, `move_buffer_to_tab` — singled out by the
  sub-agent as "the one module that does the `---@type` linkage right",
  `normal_buffer`, `safe_adjacent_buffer`, `selection`, plus the two
  top-level `buffer_utils`/`tabs_utils` files I checked directly):
  README/`@types`/code all agree exactly.
- Feature idea: none obviously missing — small, focused, single-purpose
  leaf modules throughout, each solving exactly one buffer/window/tab
  primitive.

**All five huge subsystems (`ui`, `fs`, `cross`, `bindings`, `buf_win_tab`)
are now audited.** Remaining: the `lib.lua.*` namespace (9 modules, not yet
inventoried) and the glue layer (`lib/config`, `lib/strategies/*`,
top-level `lib/@types/*`).

### lib.lua.* (16 modules, 90 files, editor-independent pure Lua) — ✅ first full pass, biggest structural bug of the audit

Not one of the five huge subsystems, but the biggest single batch after
them. `strings`/`tables` (38 files combined) delegated to a sub-agent,
every finding verified myself before acting (same process as the huge
subsystems); the other 14 modules (2-12 files each) checked directly.

- **`Lib.Strings` and `Lib.Tables` — the two top-level aggregate classes —
  were describing the wrong shape, and it was an active bug, not a gap.**
  Each `@types/init.lua` had carried two classes since inception: a
  fictional one (also named `Lib.Strings`/`Lib.Tables`) describing a
  *namespaced* shape (`strings.core.trim`, `tables.array.map`) that
  `init.lua` never returns, and a second one (`Lib.Strings.ALL`/
  `Lib.Tables.All`) that correctly described the real *flat* shape
  (`strings.trim`, `tables.map`) — but was never referenced by anything.
  Both `init.lua`s' own `---@type Lib.Strings`/`---@type Lib.Tables` on
  their `return M` pointed at the wrong (fictional) one the whole time:
  LuaLS gave **actively wrong** completions for `require("lib.lua.strings")`
  and `require("lib.lua.tables")` — promising fields that don't exist,
  silent on the ~50-60 that do. Merged each pair into one real class.
  While merging, a cross-check of every `M.<field>` actually set in each
  `init.lua` against the (now real) class turned up three more gaps the
  merge itself didn't cause: `strings.width` (the whole submodule table,
  not just its 3 flattened functions) and `strings.strip_ansi` were real
  and missing from the type; `tables.with` was real, undocumented in
  `tables/README.md`, and missing from the type. All three added.
- **`tables.functional`/`tables.unique_table` are deliberately not wired
  into `tables/init.lua`** (their `map`/`filter`/`reduce`/`unique` collide
  by name — and for `functional`, also by callback-argument-order — with
  the array-ops versions already flattened onto `M`) — but nothing said so
  anywhere; `tables/README.md` didn't mention either module exists. Added
  an "Also see" section explaining the collision and how to require them
  directly, matching the precedent `strings/README.md` already set for its
  own `transform` (a curated subset with the same kind of exclusion).
- **`strings.hex_to_string`** — real, complete, already promised by the
  (fictional) type — was never actually wired onto `strings/init.lua`'s
  `M`, unlike every sibling leaf's functions. No name collision blocks it
  (unlike `functional`/`unique_table` above), so wired it up rather than
  documenting an exclusion — same "vergessenes Submodul" remediation this
  whole audit has used everywhere else. Added its own README section too
  (previously undocumented anywhere).
- **Mechanical `---@type` gaps** (the same pattern found dozens of times
  across the five big subsystems): 10 more `strings` leaves (`core`,
  `distance`, `encoding`, `format`, `links`, `patterns`, `case`, `wrap`,
  `utf8`, `transform`) and 6 more `tables` leaves (`array`, `core`, `dict`,
  `safe`, `set`, `functional`) had a matching, accurate class already
  sitting in `@types/` but unreferenced on their own `return M`. Fixed all
  16. `time.diff`'s callable-factory `return M` had the same gap despite a
  complete `Lib.Time.Diff` class already existing — fixed.
- **`strings.location.lua`** had its `Lib.Strings.Location` data-shape
  class defined inline in the source instead of under `@types/` (the
  now-familiar `conventions.md` violation, same shape as `dev.duplicates`/
  `keymap.portability` from earlier batches) — moved.
- **`modules.md`'s `lib.lua.*` table was missing 7 of 16 modules
  entirely**: `config`, `diff`, `dump`, `error`, `numeral`, `uuid`, `yaml`
  had complete READMEs and were never linked anywhere in it. The `time`
  row only mentioned `diff`, not `format`/`presets`; the `json` row said
  "decode helpers" only, omitting `encode` entirely. Rewrote the whole
  table.
- **`docs/API/foundations-lua.md` (the parallel deep-doc file, already
  fully covering 13 of the 16 modules) was missing `class`,
  `context_manager`, and — the one module absent from *both* docs —
  `config`** entirely. Added a new "OOP / control flow / config" section
  covering all three.
- Everything else in the 14 small/medium modules (`class`, `config`,
  `context_manager`, `diff`, `dump`, `error`, `functions`, `json`, `lazy`,
  `memo`, `numeral`, `time.format`, `time.presets`, `uuid`, `yaml`, plus
  the genuinely-internal `time.diff.internal.*` helpers): README/`@types`/
  code all agree, no further findings.
- Feature idea: none obviously missing — this namespace already covers
  strings, tables, functional helpers, time/date, JSON/YAML/UUID,
  numerals, diffing, dumping, structured errors, OOP, try/finally, config
  merging, lazy-require, and memoization. Comprehensive for a
  general-purpose Lua foundation layer.

### buffer (+ buffer.context) — ✅ no issues

Leaf-only namespace by design (no `buffer/init.lua`, documented in
`modules.md:34` and self-flagged again in `buffer/@types/init.lua` as the
same stale-`Lib.Buffer`-aggregator pattern already known from `Lib.Modules`).
No dedicated top-level README, but that's consistent with the deliberate
"no unifying namespace" design — each leaf (`get_alternate`, `insert_lines`,
`is_markdown_buf`, `open_background`) is fully self-documented in its own
doc-comment, and `modules.md` already explains why. `buffer.context` (the
one submodule with its own directory) has a proper README + @types, fully
accurate.

---

## Audit complete — 2026-09-07

Every top-level `lib.nvim.*` module, all five huge subsystems (`ui`, `fs`,
`cross`, `bindings`, `buf_win_tab`), the whole `lib.lua.*` namespace, and
the glue layer (`lib.config`, `lib.strategies.*`, `lib/@types/*`) have been
audited. Every finding was fixed, committed and pushed to `main` as the
sweep went.

The recurring finding types, in rough order of how often they turned up:

1. **Forgotten features** — a real, complete, correctly-typed function that
   simply never made it into the README. At least one per batch
   (`ui.kit.compare`, `fs.path`, `cross.run_argv.run_async_captured`,
   `bindings.audit`'s three lints, `buf_win_tab.collect_win_report`,
   `strings.hex_to_string`, `autocmd.docs.write_all`).
2. **Mechanical `---@type` gaps** — `return M` with no annotation despite a
   correct class sitting in `@types/`. Found ~30 times.
3. **Actively-wrong types** (rarer, higher-impact) — the annotation exists
   but points at the wrong shape, so LuaLS gives *wrong* completions rather
   than none: `Lib.Strings`/`Lib.Tables` (nested vs. flat), `Lib.set` /
   `Lib.safe` (highlight/notify shape vs. the `tables.*` module actually
   exported).
4. **Phantom fields** — the type promises a key no aggregator provides
   (`globbable`), or an aggregator provides a key under the wrong name
   (`eager`'s `autogroup`).
5. **Inline `@class` defs** in source instead of under `@types/` (a
   `conventions.md` violation) — `bindings` ×3, `keymap.portability`,
   `strings.location`, `dev.duplicates`.
6. **Deliberate non-wiring left undocumented** — a module kept out of an
   aggregator on purpose (name/signature collision) with nothing saying so
   (`tables.functional` / `tables.unique_table`).

Deliberately **not** touched, each with the same reasoning (self-flagged
debt, or a fix that would be a breaking change for external consumers):
`Lib.Modules` / `Lib.Fs` / `Lib.Cross.ALL` / `Lib.BufWinTab` fictional
aggregator classes, the `module_annnotation` typo directory name, unused
but exactly-matching `@types` aliases next to already-self-typed bare
`return function(...)`.
