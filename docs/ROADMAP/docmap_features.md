# `lib.nvim.docmap` — shipped features

A ledger of what's been built, why it was built that way, and (where known)
the commit it shipped in. For *how to use* any of this, see
[`lua/lib/nvim/docmap/README.md`](../../lua/lib/nvim/docmap/README.md) — this
file is the decision record, not a usage manual, so it stays short per
feature: the interesting trade-off, not the full narrative. Full history
(verification steps, exact test counts, etc.) lives in git log, not here.

Extracted from `docmap_roadmap.md`/`docmap_roadmap_next.md` (now removed —
see git history of this directory for the original, much longer process
narrative each entry below compresses).

## IR & data model

- **Edge kinds** (`require`, `call`, `type`, `extends`) — one discriminated
  `ir.edges` array instead of parallel fields, so layout/filter/draw logic
  exists exactly once per concern instead of once per edge type.
- **Require-graph** (`deps.lua`) — extracted per-file (not into a throwaway
  global set like the old `check_orphans` did), with line numbers. Enables
  `require-cycle` (Tarjan SCC), `require-not-declared`, and opt-in
  `layer-violation` checks nearly for free.
- **Call-graph** (`calls.lua`) — treesitter-based (LuaLS's own `--doc` misses
  most of this repo's functions). Alias-resolves `local fs = require(...)`
  before matching call sites; deliberately **discards** unresolvable
  receivers rather than guessing. Confidence is tracked (`exact` vs.
  `heuristic`); the heuristic fallback (name matches exactly one function in
  the tree) is **opt-in**, default off — "a wrong call graph is worse than an
  incomplete one."
- **`extends` edges** (inheritance) — parents live on `defines[1].extends`
  (an array, for multiple inheritance), not `entry.extends` as originally
  guessed; verified against real `lua-language-server 3.18.2` output before
  writing code. An `@alias` never carries `extends`, even when it aliases a
  class.
- **Deferred vs. load-time requires distinguished** — a `require()` inside a
  function body (lazy) is a real edge but drawn differently (dotted) from a
  top-level one; the cycle check only complains about load-time cycles.
  Comment-only `require(...)` mentions (doc examples) are excluded.

## Checks (`check.lua`)

All info/warn severity, never error, unless noted:
`require-cycle`, `require-not-declared`, `layer-violation` (opt-in),
`dead-function` (a function with zero resolvable callers — scoped carefully:
always flags unreferenced `local function`s and `@internal`-tagged ones,
only flags ordinary exported functions under `opts.dead_code = true`, to
avoid flagging half the public API), `param-name-mismatch` (positional
comparison of the nth `@param` against the nth real parameter — not a set
comparison, which would silently pass two swapped parameters), plus the
pre-existing `missing-summary`/`undocumented-param`/`missing-readme`.

## Hierarchy tab — five views

`Modules` (children edges) / `Types` (collaboration, `kind="type"`) / `Deps`
(`kind="require"`) / `Calls` (`kind="call"`, per-*function* boxes, not
per-module) / `Inheritance` (`kind="extends"`, its own layout — doesn't use
the shared `walk()`, since a module typically declares a base class *and*
its subclasses together, which `walk()`'s per-seed-layer-0 model would
otherwise collapse onto one row; depth here is longest-path-from-a-
parentless-class instead, verified correct on a 3-level diamond fixture).

- **Direction** (`in`/`out`/`both`) and **depth** (1/2/3/∞, `MAX_HNODES=90`
  hard cap) as orthogonal toolbar axes for Deps/Calls, not separate views.
- **Backedges** get their own routing (lateral, not through boxes) and CSS
  class — the layered BFS is tree-shaped, require/call graphs aren't.
- **Keyed reconcile** (FLIP-style) instead of `innerHTML = ""` + rebuild:
  boxes tracked in a `Map<key, HTMLElement>`, enter/update/exit sets, CSS
  `transition` on `left`/`top` for the "boxes visibly migrate" feel. Edges
  are hidden during the move and redrawn after (not path-interpolated —
  cheaper, no framerate risk at 90 boxes).
- **Context menu** (right-click) — `describeTarget(el)` classifies the
  clicked element, entries filtered to what's actually available; disabled
  (not hidden) with an explanatory label when data is missing (e.g. no
  LuaLS run yet), same pattern the Types view already used.
- **Semantic zoom** — mouse-wheel geometric zoom (`transform: scale()` on a
  `#hstage` layer, position math untouched) plus a **separate** semantic
  zoom: crossing an asymmetric threshold with hysteresis
  (`DRILL_IN z≥1.80 → z:=0.90`, `DRILL_OUT z≤0.55 → z:=1.15`, 260ms cooldown)
  re-centers on the module under the cursor. Naive symmetric thresholds
  flicker; the fix was firing only on *crossing* the threshold, not on
  being in a state past it — otherwise any further wheel motion in *either*
  direction re-triggers. Drilling on the already-centered box is a no-op,
  not a reset. Deps/Calls map the same gesture to `depth ±1` instead (a
  require graph has no "one level in/out" the way a tree does).
- **LOD** — below ~0.65 scale, box detail lines hide (name only); pure CSS
  class toggle, no re-render.

## Navigator (`:LibBrowse`)

Editor-side counterpart to the HTML page — `layout.mount` (list/detail/
status, 3 slots), same modes as the browser (`1`-`4` = Structure/Deps/Calls/
Types, plus a 5th, History), `j`/`k` move with detail following immediately,
`<CR>` drills in or follows an edge, `-`/`<BS>` out, `<C-o>`/`<C-i>` visit
history, `h`/`l` direction, `+`/`_` depth, `gd` opens source (closes the
view — floats sit over the whole editor, "jump to a file you can't see"
isn't a jump), `gq` current list → quickfix, `/` fuzzy-jumps via
`ui.kit.picker`.

- **Artifact-first, not scan-first.** `module_map.json` read (~10ms) beats a
  live `scan()` (~0.65s, measured) by ~65×; `:LibBrowse live` opts into
  `install({watch=true})` when the 0.65s is acceptable. A live-file mtime
  check flags a stale artifact instead of silently showing wrong data.
- **History mode** (`:LibBrowse history`) — commit list → functions a diff
  touched (with caller counts) → `<CR>` on a function leaves History for
  **Calls (incoming)** rather than building a third bespoke "callers" list —
  same underlying question, already-answered by an existing mode.

## Analysis tab

Tool-selector toolbar (not a diagram) — panels are tables/rankings over the
IR, not graph boxes; closer to the Notes tab than the Hierarchy tab
architecturally. Four tools shipped, each a pure `ir -> result` function
(same shape as a `Check`, result is a table instead of a findings list):

- **Test coverage** (`coverage.lua`) — `fn.tested` via the same
  identifier-counting technique `calls.lua` already uses, run against
  `docs/TESTS/*_spec.lua` instead of the source tree. Replaces the manual
  `@test` tag (0 real uses in the wild) without removing the tag itself.
  Renders only a positive "tested" badge, never an "untested" warning — the
  heuristic has a real, documented blind spot (indirectly-tested functions
  never named in a spec), and a warn-badge on most of ~600 functions would
  be noise, not signal.
- **Documentation coverage** (`doccoverage.lua`) — one definition of
  "documented" shared by `M.resolve` *and* `M.summary` (so they can't drift
  apart), matching the three existing findings exactly rather than
  inventing a second, possibly-different rule. `@return` deliberately
  excluded — unlike parameters, there's no structural fact in the raw
  signature to check an `@return` line against. Optional `coverage.svg`
  badge, hand-drawn rather than fetched from shields.io (a network call
  during `scan_full()` would make `--check` network-dependent).
- **Fan-in/fan-out** (`renderAnalysisDeps`) — pure client-side aggregation
  over already-serialized `n.requires`/`n.required_by`, no new Lua
  extraction. Sorted by fan-in descending (the module with the most
  dependents first — "what breaks most if I touch this").
- **Cyclomatic complexity** (McCabe: 1 base + one point per
  `if`/`elseif`/`while`/`for`/`repeat` + one per `and`/`or`) — node types
  verified empirically against a real parsed tree before writing the
  query, not guessed. Computed unconditionally during the main scan (needs
  the treesitter node itself, which only exists during that one pass),
  unlike the other three tools which resolve lazily. Ranks by *function*,
  not module average — a module average would hide the one genuinely
  complex function inside an otherwise healthy module.

## Notes & Index tabs

- **Notes tab** — `@deprecated` (pre-existing data, never collected before)
  plus new `@todo`/`@bug`/`@test` tags. These are **arrays**, not
  `string?` — a function with two open todos has two todos; a scalar would
  silently drop the second. Verified `lua-language-server` neither knows
  nor warns about the new tags before introducing them (a tag that
  triggers an LSP warning on every use would defeat the point). Empty
  sections render an explicit "nothing here" instead of disappearing, so
  "genuinely empty" stays distinguishable from "not collected."
- **Index tab** — alphabetical, by **bare name** (`M.read` sorts under
  **R**), not the raw identifier — the `M.` prefix is this repo's local
  convention, not part of the function's actual name; sorting by raw
  identifier would collapse the majority of entries onto "M". Names with a
  non-alphabetic start (`_evict`) get their own `#` bucket instead of being
  dropped. A second, module/namespace-level A-Z index exists alongside the
  function index (same jump-bar code, reused not duplicated).

## Cross-project linking (`tagfiles.lua`)

`opts.tag_files = { "prefix" = "path/to/other/module_map.json" }` resolves
an otherwise-inert `requires_external` box against another project's own
committed map, turning a dead gray box into a real, clickable link into
that project's page. Deliberately **local paths only, no URLs** — a network
fetch during `scan_full()` would make `--check` network-dependent, the same
reasoning that kept the DOT export decoupled from an actual `dot` binary.

## Commands

`:LibMap` (generate), `:LibMap check`/`full` (drift-check / LuaLS-enriched
run), `:LibMap open` (prefers a running `:LibMap serve` over `file://`),
`:LibMap graph {deps|calls} [module]` (opens the HTML view pre-centered),
`:LibMap why <a> <b>` (shortest require-path between two modules — BFS,
distinguishes load-time from lazy edges in the answer, since that's the
difference between "must go" and "fine as-is"), `:LibMap diff <ref>`
(structural diff between two revisions — modules/functions/deps/cycles/
blast-radius added or changed; tolerates older schema versions rather than
failing on them), `:LibMap impact [ref]` (→ quickfix: what a diff touches,
transitively, live-computed, no artifact needed — default `ref` is `HEAD`,
so a clean tree's blank `:LibMap impact` answers "what does my uncommitted
work affect"), `:LibMap serve [stop]` (local-only HTTP server, see below),
`:LibMap graph --dot` (Graphviz export).

## Commit history with blast radius (`history.lua`, `:LibMap serve`)

The one feature Doxygen doesn't have: click a commit, see which functions
it touched, who calls those functions, which modules that reaches
transitively.

- **Can't be embedded in the committed artifact** — `--check` byte-compares
  committed vs. freshly-generated output; embedding `git log` data creates
  a commit that invalidates its own artifact the moment it lands (no fixed
  point exists). Ruled out the "just add a History tab like the others"
  approach specifically, not the browser view as a whole.
- **A `file://`-origin page can't `fetch()` a neighbor file either**
  (opaque origin, CORS blocks it in real browsers) — ruled out "cache file
  next to the HTML" as the workaround.
- **Resolved with a real (but strictly local) HTTP server**
  (`serve.lua`, ~150 lines on `vim.uv`, no new dependency) —
  `:LibMap serve` binds `127.0.0.1` only (never `0.0.0.0`), validates
  `<sha>` against `^[0-9a-f]{7,40}$` before it ever reaches `git` (verified
  against real injection attempts with curl: `--upload-pack=…`, `$(id)`,
  `abc;id`, path traversal, oversized/undersized hashes — all rejected with
  400, none reach git), rejects `HEAD` too (a whitelist with exceptions
  isn't one), and tears down on `VimLeavePre`.
- **Costs are lazy** — a commit detail costs ~0.3s (measured), computed on
  click, vs. ~25-50s to precompute all resolvable history up front. This is
  *why* the server approach won over a static snapshot file, not just a
  nice property of it.
- **Three degrade states, not one**: exact attribution; *approximated*
  (older commits before `fn.line_end` existed — approximated as "next
  function's start minus one," verified this never over- or
  under-attributes on real commits including a pure-insertion one that
  correctly reports zero approximation); and *revision older than the map*
  (degrades to "files only," doesn't error on a missing parent artifact).
- **`:LibBrowse history`** is the editor-side equivalent — no server
  needed (the editor never had the `file://` origin restriction); `<CR>`
  on a touched function leaves History for Calls-incoming rather than
  building a redundant third view.

## Reuse & operations

- **`install()` / `uninstall()`** — programmatic entry point returning a
  live handle (`handle.ir()`, `.node(id)`, `.on_change(fn)`); `watch=true`
  attaches a debounced `BufWritePost` autocmd instead of requiring a manual
  `:LibMap` per edit. `command.setup()` (what `:LibMap` itself is) is now a
  thin `install({watch=false})` call, so lib.nvim's own behavior didn't
  change when this was added underneath it. Idempotent teardown by design.
- **`cli.lua`** — the `--check`/`--full` logic extracted out of
  `scripts/gen_map.lua` into `run(opts, argv) -> exit_code`, with no
  `vim.cmd("cq …")` inside it (that stays the caller's job, so the function
  itself stays plain and testable). `scripts/gen_map.lua` itself shrank to
  3 lines that any consuming plugin copies verbatim.
- **Reusable pre-commit hook template** — three variables
  (`SOURCE_DIR`/`OUT_DIR`/`GEN_SCRIPT`) at the top of
  `scripts/hooks/pre-commit`, everything else generic shell. Deliberately
  **checks, doesn't regenerate-and-stage** — a hook that regenerates and
  stages produces diffs nobody intended, and interacts badly with
  `--amend`/rebases. Local (`core.hooksPath`) chosen over a tool like
  `lefthook` specifically *because* this needs to be portable to whatever
  repo copies it — `lefthook` would impose an extra dependency on every
  *consumer* of `lib.nvim`, not just this repo.
- **DOT/Graphviz export** — same edge-walking core as the Mermaid renderer;
  gives ranking/clustering/print-quality output Mermaid and the in-browser
  layered-BFS both lack.
- **`gO`** — jump from `:LibBrowse` straight into the HTML page at the same
  mode/center/direction/depth/function, since the browser page's entire
  state already lives in its URL fragment; effectively `format()` +
  `:LibMap open`.

## Tag adoption

`@internal` propagated to the function level (previously module-level
only) — applied to the 15 exported functions in the one directory
(`lua/lib/lua/time/diff/internal/`) that's actually a real, non-anonymous
`internal/` convention match; incidentally surfaced two already-dead
functions there, left in place (cleanup wasn't this task's job, the
`dead-function` finding now correctly names them). `@todo`/`@bug`/
`@deprecated` adoption: genuinely nothing to convert — every "deprecated"/
"legacy" mention in the tree turned out to reference a Neovim API
deprecation being worked around, not a `lib.nvim` function actually
replaced by another. `@see`: one real pair added
(`fs.scan_cached.scan` ↔ `fs.scan_roots.scan`, session cache vs.
disk-persistent cache of the same walk) where the module headers already
described each other as counterparts but never linked at the function
level.
