# `documentation.nvim` × `lib.nvim.telemetry` — runtime truth for a static analyzer

> **Status:** concept, not implemented. Written in response to: "prüfe, ob
> documentation.nvim dieses Telemetry-Modul verwenden könnte, also wenn es
> installiert ist, dann einen neuen Tab 'telemetry' einfügen, dort der Report
> sichtbar + weitere interessante Stats".
>
> **Verdict: yes — and the tab is the least interesting part of it.** The
> valuable thing is a join neither tool can produce alone: documentation.nvim
> knows what *exists and is documented*, telemetry knows what *actually ran*.
> Everything below was checked against documentation.nvim's actual source.

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
wrap list and the observed keys. What is missing is only the ability to read a
namespace's counts **without a live instance**, i.e. straight off disk: a
`:DocMap check` run in a fresh Neovim has no telemetry instance for the tree it
is analyzing.

**One small addition to lib.nvim, then:**

```lua
telemetry.load(namespace, opts)  -- -> Lib.Telemetry.Data|nil, read-only
```

Thin wrapper over the existing `store.load()`, which already does exactly this
and is already namespaced, sanitized and merge-on-write. No new file format,
no new IO.

## Key-matching is the one real problem

Telemetry keys are what the wrap call labelled them:
`t.wrap(require("lsp.servers"), "servers")` yields `servers.attach`.
documentation.nvim's IR keys are `module_id .. "#" .. fn.name`
(`check.lua:686`). Those do not line up on their own.

This is where the concept could quietly produce wrong answers, so it needs to
fail loudly instead:

- **Match on the module's real Lua module path, not the wrap prefix.** That
  means telemetry should record the prefix *and* enough to resolve it — or,
  simpler and more honest, documentation.nvim should only join namespaces
  whose keys it can resolve, and report the rest as "unmatched" rather than
  silently treating unmatched as never-called.
- **"Unmatched" must never render as ☠️.** A function telemetry has no opinion
  about is not a dead function; it is a function with no data. The mode must
  distinguish *no data* from *zero calls*, and the `dead-function` check must
  only be suppressed or escalated on a real match.
- `wrap_lib()`'s aggregate keys (`trim`, `find_root`) are flat and correspond
  to `MODULE_MAP` entries, not to module paths — those need the strategy's own
  mapping to resolve, which `lib.strategies.control` can already enumerate.

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

| Piece | Repo |
| --- | --- |
| `telemetry.load(namespace)` — read counts off disk without an instance | lib.nvim |
| Key-resolution helper (wrap prefix ↔ module path), or the honest "unmatched" contract | lib.nvim |
| Mode 7 + entry builder + join logic | documentation.nvim |
| `dead-function` suppression/escalation from runtime evidence | documentation.nvim |
| The two `doccoverage` aggregate lines | documentation.nvim |

The bulk is documentation.nvim's, so the consumer half belongs in **its** own
roadmap; this document is the lib.nvim-side contract plus the reasoning for
why the join is worth building at all.

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
