# `lib.nvim.docmap` — open items

What's actually still open for docmap, after a full pass through its
(now-removed) roadmap history. Everything shipped is recorded in
[`docmap_features.md`](docmap_features.md) instead — commit hashes and
design decisions live there, not here. This file only holds things with no
decision yet, or a decision to *not* build something (a documented rejection
is as much a result as a shipped feature, and worth keeping so the question
doesn't get re-litigated from scratch).

Consolidates and replaces `docmodule.md`/`docmodule_NEXT.md` (moved in from
the nvim-config repo, 2026-07-28), `module_map.md`, and
`docmap_hierarchy_and_integrations.md` — all fully superseded by what
actually got built; see git history of this directory if the original,
much longer process narrative is ever needed.

## Genuinely open

### mdview.nvim integration — never built

Concept existed (originally `docmap_hierarchy_and_integrations.md` Part 4),
LuaLS enrichment / Hierarchy tab / `install()` (that doc's Parts 1–3) all
shipped in more complete form than sketched there, but the mdview piece
itself was never started — confirmed by grep, no `mdview` reference
anywhere under `lua/lib/nvim/docmap/`.

**Tier A** (buildable without any mdview.nvim change): a new
`render/mdview.lua` producing markdown shaped for what mdview's `ammonia`
sanitizer's *default* builder actually keeps (`<details>`/`<summary>`,
GFM tables, inline code — no custom CSS classes or `style` attributes,
badges conveyed through text/emoji instead), pushed via mdview's existing
`ws_client.send_markdown(path, markdown, opts)` from `install()`'s
`on_change` hook, guarded by `pcall(require, "mdview.core.state")` so
lib.nvim never hard-depends on mdview.

**Tier B** (a real box+connector diagram inside mdview's own browser tab):
not buildable today — mdview's pipeline is markdown-in/sanitized-HTML-out
with no structured-data render mode. Needs a `kind` field on mdview's own
WS protocol and a client branch that skips comrak/ammonia for
`kind = "structured"`. Belongs in a concept doc in mdview.nvim's own repo,
not here — don't design it twice.

**Two things to verify before Tier A starts** (unresolved when this was
last looked at):
1. Ammonia's exact default attribute allowlist — confirmed the sanitizer is
   `ammonia::Builder::default()` and that mdview only adds `data-sourcepos`
   + the checkbox `<input>` beyond that default, but never read ammonia's
   own crate source to confirm which attributes (e.g. `id`) survive.
2. How a browser tab gets pointed at a *specific* room vs. the
   currently-open buffer's path — `send_markdown` accepts any string as a
   room key, but the routing from a URL to that key wasn't traced.

### Analysis-tab candidates — not yet spec'd

Four tools already shipped (test coverage, doc coverage, fan-in/fan-out,
cyclomatic complexity — see `docmap_features.md`). Two more were identified
as the next-most-valuable but deliberately not built yet, because they're
the most expensive of the candidates considered and hadn't earned their
cost until the tab itself was proven useful with cheaper tools first:

- **Code duplicates** (PMD/CPD-style "copy-paste detector") — structural
  similarity of function bodies across ~250 files. The pattern most likely
  to go unnoticed in a utility library specifically.
- **Churn-hotspots** (Adam Tornhill's *Your Code as a Crime Scene*: git
  history × complexity) — modules that are both *frequently changed* and
  *complex*, the actual refactor-risk signal that neither metric alone
  gives.

Revisit once the Analysis tab (now with four tools) is actually being used
day to day — building the expensive tools before that is optimizing for a
usage pattern that isn't confirmed yet.

## Deliberately not building (documented rejections)

Keeping the reasoning here so the question isn't re-asked from a blank
slate — none of these are "forgot," all were considered and turned down
for a stated reason. Revisit only if the stated condition changes.

| Idea | Why not | Revisit if |
|---|---|---|
| **Source-Browser** (Doxygen's `SOURCE_BROWSER=YES`, inline syntax-highlighted source with clickable cross-refs) | `:LibBrowse`'s `gd` already jumps into the real editor at the real line — strictly better than a static HTML view for actual use | Someone needs to browse source without the repo checked out locally |
| **Extract docmap into its own plugin** (O2) | 22 files / 8682 lines — clearly bigger than lib.nvim's usual small utilities, but no current pain point forcing the split; docmap only depends on `lib.nvim.ui.kit` internally, and the `install()`/`command.setup()` registration is already built so an external plugin could reuse it 1:1 without docmap itself changing | The size/coupling actually starts hurting, not just looks large. Naming survey + related-plugin feature research already done, see below — kept ready, not acted on |
| **Full-text search** (Doxygen search index over prose/`@example` blocks, vs. today's name/module/summary-only search) | Real value, but the existing search already covers the daily case (find a module/function); the prose volume in this tree hasn't grown enough to make it bite | Prose volume in the tree grows substantially |
| **`@group`/`@ingroup`** (Doxygen's `\defgroup`, cross-cutting groups independent of directory structure) | High cost (new tag, new aggregation, new view) for a need that's never come up in a 250-file utility tree where modules already *are* the sensible grouping | The repo grows to where "all public APIs, cross-module" becomes a real question |
| **`ctags` export** (`:LibMap tags`) | Anyone with LSP already has `gd`/`gr` via `lua-language-server` — practically everyone who installs `lib.nvim` at all. Only helps non-LSP external tooling, which nobody here uses | Someone needs `lib.nvim` symbols from outside LSP-aware tooling |
| **Live-reload of the HTML page** on save | `:LibBrowse live` already covers the "see changes without a manual regen" need, in the editor, without a second running process/browser tab to keep in sync | `:LibBrowse live` stops being sufficient for some reason |
| **Runtime inspection of a loaded module** (`:LibInspect`, backlog item B1) | Explicitly out of docmap's scope, not deferred *within* it — actually executing/requiring code is a different trust model (side effects, time-dependent, can never feed `--check` or a committed artifact) than docmap's pure static scan. A separate future tool, if built at all | Someone actually starts that tool — open design questions noted below |

**B1 open design questions, if `:LibInspect` is ever started:** cycle/depth
limits when walking a live table, whether to call into `__index` functions
or just report them, and whether the result even belongs in a `ui.kit`
window or somewhere else entirely.

## O2 prep — naming survey + related-plugin feature research (2026-07-28)

Not a decision to pursue O2, just work already done so it's not repeated
if/when the question comes up for real.

### Names checked against GitHub

| Name | Status |
|---|---|
| `dooku.nvim` | **Taken** — [Zeioth/dooku.nvim](https://github.com/Zeioth/dooku.nvim), same problem space |
| `docgen.nvim` | **Taken, twice** — [jamestrew/docgen.nvim](https://github.com/jamestrew/docgen.nvim), [dhananjaylatkar/docgen.nvim](https://github.com/dhananjaylatkar/docgen.nvim) |
| `cartographer.nvim` | **Taken, twice** — [Iron-E/nvim-cartographer](https://github.com/Iron-E/nvim-cartographer) (keymap DSL), [hkupty/cartographer.nvim](https://github.com/hkupty/cartographer.nvim) (archived 2021) |
| `wayfinder.nvim` | **Taken** — [error311/wayfinder.nvim](https://github.com/error311/wayfinder.nvim), and close enough in concept to `:LibBrowse` to risk real confusion even if it weren't |
| `doxygen.nvim` | Not confirmed formally trademarked, but avoid anyway — reusing a distinct, well-known project's exact name for something unrelated reads as a claimed affiliation that doesn't exist |
| `docmap.nvim` | Open. Matches the existing code/command names (`docmap`, `:LibMap`, `:LibBrowse`) — safest choice, no re-branding for anyone already using it via lib.nvim |
| `docgraph.nvim` | Open. States what it is (doc + require/call/type/inheritance graphs) with no metaphor |
| `luagraph.nvim` | Open. Leads with the static-analysis/graph angle over the doc-site angle |
| `codeatlas.nvim` | Open. "Atlas" (a book of maps) extends the metaphor to match the Doxygen-parity breadth better than "map" alone |
| `structura.nvim` | Open. Drops the map metaphor entirely — neutral, more "serious tool" reading |

Re-check before actually registering — availability changes.

### Related-plugin feature survey

Two of four repos found while researching names turned out relevant, two
didn't:

**Not relevant** — [hkupty/cartographer.nvim](https://github.com/hkupty/cartographer.nvim)
(archived project/file/regex/TODO finder, author recommends telescope.nvim
instead; nothing about analysis or graphs) and
[Iron-E/nvim-cartographer](https://github.com/Iron-E/nvim-cartographer) (a
keymap-definition DSL, unrelated to documentation entirely — a name
collision only, not a feature one).

**[dooku.nvim](https://github.com/Zeioth/dooku.nvim)** — same problem space,
opposite architecture: a thin wrapper shelling out to *external*
per-language doc generators (Doxygen/Typedoc/JSDoc/Rustdoc/Godoc/LDoc/Yard)
and opening the HTML result. docmap's own-treesitter-analysis, zero-external-
tool-dependency approach is a deliberate, worth-keeping difference, not a
gap. Its generate-on-write option is the "regenerate on save" idea already
rejected above (unintended diffs); `:DookuOpen` is already `:LibMap open`.
Nothing here worth adopting.

**[wayfinder.nvim](https://github.com/error311/wayfinder.nvim)** — closest
relative of `:LibBrowse`, genuine candidates if `:LibBrowse` gets revisited
(none currently scheduled, listed roughly cheapest/most-valuable first):
1. **`?` key-hint overlay** and **`:checkhealth docmap`** — both small,
   immediately useful, match patterns already used elsewhere in this
   plugin family (e.g. recommender.nvim's own `?` keymap).
2. **Trail** — pin interesting nodes while exploring (wayfinder's `p`/`a`/
   `A`), separate from plain back/forward history, which is all
   `:LibBrowse` has today (`<C-o>`/`<C-i>`).
3. **Saved Trails** — name and persist an exploration path across sessions
   (Neovim state, not the repo) — fits docmap's own scope (navigation
   state, not runtime execution, so it doesn't cross into B1's territory).
4. **Local list filter** with negation/quoted phrases, narrowing the
   *current* Deps/Calls list in place — different from `:LibBrowse`'s
   existing `/`, which fuzzy-jumps across everything.

Already covered, no gap: wayfinder's quickfix export (`x`) is already
`:LibBrowse`'s `gq`.
