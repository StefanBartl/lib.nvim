# `documentation.nvim` × `lib.nvim.telemetry` — runtime truth for a static analyzer

> **Status: fully shipped (2026-08-04).** The lib.nvim-side contract shipped
> first, as `telemetry.load()` + module-id resolution
> (`Lib.Telemetry.WrapOpts.module_id`, `inst.resolved_modules()`,
> `Data.modules`) — since moved to `runtime-analysis.telemetry` along with
> the rest of this module (see the Update note below). The consumer half —
> mode 8 (not 7; see that note), the `dead-function` join, the two
> `doccoverage` aggregate lines — landed in documentation.nvim as
> `documentation.core.telemetry_join` + a `telemetry` mode in `:DocBrowse`,
> exactly the shape proposed below. See documentation.nvim's own
> `docs/ECOSYSTEM.md` step 8 for the full writeup, and
> `runtime-analysis.nvim`'s `docs/FINISHED.md` for that repository's side.
> Written in response to: "prüfe, ob documentation.nvim dieses
> Telemetry-Modul verwenden könnte, also wenn es installiert ist, dann einen
> neuen Tab 'telemetry' einfügen, dort der Report sichtbar + weitere
> interessante Stats".
>
> **Verdict: yes — and the tab is the least interesting part of it.** The
> valuable thing is a join neither tool can produce alone: documentation.nvim
> knows what *exists and is documented*, telemetry knows what *actually ran*.
> Everything below was checked against documentation.nvim's actual source.
>
> **Update (2026-08-03):** the module this document is about has moved.
> `lib.nvim.telemetry` is now `runtime-analysis.telemetry`, in the sibling
> `runtime-analysis.nvim` repo (`docs/ECOSYSTEM.md` step 7, in
> documentation.nvim). `:LibTelemetry` is now `:RATelemetry`. `wrap_lib()`
> was **not** migrated — it was deleted, and lib.nvim gained
> `lib.strategies.telemetry_wrap` as its self-contained replacement: one
> `setup()` call creates the instance, materializes the metatable-hidden
> aggregate, wraps it and starts it — a caller needs neither
> `runtime-analysis.telemetry`'s API nor `lib.strategies.control`'s.
> Everything else below — `telemetry.load()`,
> module-id resolution, the honest-limits reasoning, the proposed Mode 7
> shape — carried over unchanged; only the require paths and command name
> the reasoning refers to changed, not the reasoning itself. Left
> unrewritten below deliberately, as a record of the design at the time it
> was made; treat every `lib.nvim.telemetry`/`:LibTelemetry`/`wrap_lib()`
> mention past this point as historical.

## The tab is easy; say so and move on

`:DocBrowse` is already mode-based. `lua/documentation/editor/browse/init.lua`
holds `local MODES = { "structure", "deps", "calls", "types", "history",
"trail" }`, binds `1..#MODES` from that list in a loop, renders the `?` panel
from it, and dispatches entry-building on `st.mode`. Adding a 7th mode is:
one string in `MODES`, one entry builder, one branch in the dispatch. The key
binding, the help panel and the whichkey registration all follow automatically
because they iterate the table.

There is even a precedent for a mode whose data does **not** come from the IR:
`history` is documented in that file as "the one mode whose data does not come
from the IR". A `telemetry` mode would be the second.

So the mechanical question is settled. The real question is what to *put* in
it, because "the same report you can already see with `:LibTelemetry`" is not
worth a mode.

## The finding that justifies it: static-dead vs. runtime-dead

`documentation.nvim` already ships `check_dead_functions`
(`lua/documentation/core/check.lua:682`). It is **purely static**: it builds a
`called` set from `call` edges in the IR, plus `@see` targets, plus
`local_refs`, and reports anything left over as `dead-function`.

Its own source is candid about where that breaks:

- a function bound as a **callback** (`vim.system(cmd, on_exit)`) "never gets
  a call edge no matter how public its name is" — the comment explaining why
  `local_refs` had to be folded into the `used` test, or the check "would have
  reported every callback in the tree passed by value";
- **dynamic dispatch** is invisible (the same blind spot `calls.lua` has);
- and structurally: it can only see callers **inside the analyzed tree**. For
  `lib.nvim` specifically — a library whose entire purpose is being called
  from *other* repos — every genuinely-used public function looks dead.

Telemetry answers the exact complement, from the other direction, with no
static analysis at all: *this function was entered N times in the last 30
days*. Its own blind spots are the mirror image (only calls through the
wrapped table; a reference cached before `start()` is invisible).

Cross them and each one's blind spot is covered by the other's evidence:

| | **static: has a caller** | **static: no caller found** |
| --- | --- | --- |
| **runtime: called** | normal, healthy | ⚠️ **`dead-function` false positive** — callback / dynamic dispatch / cross-repo consumer. Telemetry *proves* it is alive. |
| **runtime: never called** | 🧊 **cold path** — reachable, but nothing exercised it in 30 days. Not dead; a test-coverage or feature-usage question. |  ☠️ **high-confidence dead** — both methods agree, and they fail differently. |

The bottom-right cell is the one worth having. Neither tool can produce it:
static analysis alone yields false positives it openly documents; runtime
alone cannot distinguish "never called" from "never loaded".

The top-right cell is arguably as valuable in the other direction — it is a
**suppression list for `dead-function`**, derived from evidence rather than
from someone adding `@see` to shut the check up.

## What `documentation.nvim` needs from `lib.nvim`

Almost nothing new. `telemetry` already exposes both halves:

```lua
local telemetry = require("lib.nvim.telemetry")   -- pcall-guarded

telemetry.instances()                -- discover, no registration needed
inst.coverage()                      -- { called = {...}, uncalled = {...} }
inst.report({ since = "30d" })       -- per-function calls/timing/errors
```

`coverage()` exists precisely for this — it is the set difference between the
wrap list and the observed keys. What was missing was only the ability to
read a namespace's counts **without a live instance**, i.e. straight off
disk: a `:DocMap check` run in a fresh Neovim has no telemetry instance for
the tree it is analyzing. **Shipped:**

```lua
local data = telemetry.load(namespace, opts)  -- Lib.Telemetry.Data|nil, read-only
```

Thin wrapper over `store.load_readonly()`, itself a small variant of the
existing `store.load()` (already namespaced, sanitized, merge-on-write). No
new file format, no new IO — the one behavioral difference from `load()` is
the one that matters here: it returns `nil`, not a well-formed empty table,
when nothing was ever persisted for `namespace`. `load()` can't do that and
stay correct for its actual caller (a live instance's `base`, which always
wants *something* to merge into); a namespace with no live instance needs the
distinction instead — "never enabled here" (`nil`) vs. "enabled, zero calls"
(a `Data` with empty `functions`). Collapsing those two is exactly how this
concept would quietly turn "no data" into a graveyard.

## Key-matching is the one real problem

Telemetry keys are what the wrap call labelled them:
`t.wrap(require("lsp.servers"), "servers")` yields `servers.attach`.
documentation.nvim's IR keys are `module_id .. "#" .. fn.name`
(`check.lua:686`). Those do not line up on their own.

This is where the concept could quietly produce wrong answers, so it needs to
fail loudly instead — **shipped as "record it, don't guess it":**

- **`wrap_loaded()` resolves every key automatically.** Its keys are already
  derived from a real `package.loaded` path (that is the whole mechanism —
  see its own doc-comment), so at wrap time lib.nvim knows the exact module
  path and records it, rather than making a consumer reconstruct it later by
  parsing the key. A plain `wrap()` call resolves only if the caller passes
  `opts.module_id` explicitly — `t.wrap(require("lsp.servers"), "servers")`
  does **not** resolve on its own, because `"servers"` is a caller-chosen
  label, not necessarily `"lsp.servers"`, and guessing that equivalence is
  exactly the wrong-answer risk this section exists to close off.
- **The mapping is queryable live and persisted to disk.**
  `inst.resolved_modules()` returns `{ [key] = module_id }` for the current
  process; the same map lands in `Data.modules` on every flush, so
  `telemetry.load(namespace)` — no live instance required — returns it too.
  documentation.nvim builds its join key as `data.modules[key] .. "#" ..
  key:match("([^.]+)$")` for any `key` present in `data.modules`, and treats
  every other key as **unmatched**, never as "no calls".
- **"Unmatched" must never render as ☠️.** A function telemetry has no opinion
  about is not a dead function; it is a function with no data. The mode must
  distinguish *no data* from *zero calls*, and the `dead-function` check must
  only be suppressed or escalated on a real match — i.e. only on a key present
  in `data.modules`.
- **`wrap_lib()`'s aggregate keys stay deliberately unresolved.** `trim`,
  `find_root` etc. are flat and correspond to `MODULE_MAP` entries private to
  the "metatable" strategy, not to module paths, and resolving them would
  need a strategy-wide key→path registry that does not exist yet (`lib.
  strategies.control` enumerates *keys*, not where they resolve to) — a
  bigger, separate change with no motivating caller today. This is also why
  the Honest Limits section below already recommends `wrap_loaded()` over
  `wrap_lib()` for dead-surface analysis specifically: it is the one that
  resolves.

## Proposed shape

**Mode 7, `telemetry`** — a list like every other mode, sorted by calls
descending, with the join state as a leading badge:

```
  ☠️  documentation.core.duplicates#find_clones      0 calls · no static caller
  ⚠️  documentation.core.scan#on_exit               1 204 calls · no static caller
  🧊  documentation.core.churn#rebuild                  0 calls · 3 static callers
      documentation.core.check#run                 8 021 calls · 12 static callers
  ·   documentation.core.json#encode                  no telemetry data
```

`gd` (source), `gq` (quickfix) and `p` (pin) already work per-entry in every
mode and would work here unchanged — which is most of the value: a quickfix
list of high-confidence dead functions is directly actionable.

**Plus two aggregate lines** in whatever documentation.nvim already renders for
`doccoverage` — because "documented" and "used" are the two axes that matter
for a maintenance-cost number, and it already computes the first:

- *documented but never called* — the maintenance-cost set.
- *called but undocumented* — the inverse, and the better prioritized
  documentation backlog than "everything undocumented, alphabetically".

That second one is, I suspect, the most immediately useful number in this
whole document: it sorts the documentation backlog by evidence of actual use.

## Where the work lives

| Piece | Repo | Status |
| --- | --- | --- |
| `telemetry.load(namespace)` — read counts off disk without an instance | runtime-analysis.nvim (moved from lib.nvim) | **done** |
| Key-resolution (`WrapOpts.module_id`, `resolved_modules()`, `Data.modules`), honest "unmatched" for the rest | runtime-analysis.nvim (moved from lib.nvim) | **done** |
| Mode 8 (not 7 — see the Status note above) + entry builder + join logic | documentation.nvim | **done** |
| `dead-function` suppression from runtime evidence | documentation.nvim | **done** — suppression only, never escalation, per this document's own Honest Limits section |
| The two `doccoverage` aggregate lines | documentation.nvim | **done** |

The bulk is documentation.nvim's, so the consumer half belongs in **its** own
roadmap; this document is the lib.nvim-side contract plus the reasoning for
why the join is worth building at all. The lib.nvim side has since moved to
`runtime-analysis.nvim` (see the Update note above) — covered there by
`docs/TESTS/telemetry_spec.lua` and documented in
`lua/runtime-analysis/telemetry/README.md`.

## Honest limits

- **Absence of runtime data is not evidence of death**, and every part of the
  UI has to hold that line. A tree analyzed on a machine where telemetry was
  never enabled must render as "no data" everywhere, not as a graveyard.
- **30 days of one person's usage is a narrow sample.** A function used only
  during release, or only on Linux, or only by a consumer repo, is cold here
  and alive in reality. ☠️ is a *prompt to look*, never a delete list — the
  same framing `dead-function` already uses by emitting `info`, not `warn`.
- **Only calls through the wrapped table are seen** (telemetry's existing
  limit). For `lib.nvim`'s own instance that means `wrap_lib()` covers the
  aggregate, and a consumer's direct `require("lib.nvim.fs.mkdirp")` is
  invisible — which would make `mkdirp` look cold while being heavily used.
  This is the single biggest way the join could mislead, and it argues for
  wrapping modules rather than the aggregate when the goal is dead-surface
  analysis specifically.
- **`documentation.nvim` must not hard-depend on telemetry.**
  `pcall(require, "lib.nvim.telemetry")`, mode absent when unavailable — the
  same discipline that keeps `fidget` optional in `lib.nvim.progress`.
