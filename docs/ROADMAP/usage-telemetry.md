# `lib.nvim.telemetry` — opt-in call tracing & usage statistics

> **Status: implemented.** Phases 1–5 ship as `lib.nvim.telemetry`; the module
> reference is [`lua/lib/nvim/telemetry/README.md`](../../lua/lib/nvim/telemetry/README.md)
> and the spec is `docs/TESTS/telemetry_spec.lua`. Phase 6 (`wrap_tree`) is
> deliberately not implemented — see [Implementation phases](#implementation-phases).
> The [Open questions](#open-questions) below are answered, each with what was
> chosen. **This document is now a design record**; the README is the
> authoritative API reference, and implementing this doc again would duplicate
> the module.
>
> Written in response to: "ein Modul,
> das man ein- und ausschalten kann und alle Aufrufe zählt — nach 7 Tagen
> nachschauen, wie oft wurde lib.xy aufgerufen, mit welchen Argumenten, und
> wenn eine Funktion zu 90 % dasselbe Argument bekommt, kann man den Pfad
> vorne abfangen. Ausgeschaltet: wenig bis kein Performance-Impact."
>
> Everything below was checked against the actual `lib.nvim` source. Where an
> approach is ruled out, it is ruled out for a verified reason, not a guessed
> one — the `loaded[key]` cache in `strategies/metatable.lua` in particular
> constrains the whole design and is easy to miss.

## The two things being asked for

They are related but not the same, and the design has to keep them apart:

1. **Counting** — "how often was `lib.strings.trim` called in the last 7
   days?" Cheap, aggregate, survives restarts. This is the part that is
   actually useful a week later.
2. **Argument profiling** — "which arguments, how often?" This is the part
   that turns into the optimization insight ("90 % of calls pass the same
   value → memoize, or short-circuit before the function body"). It is
   *much* more expensive than counting and must be separately switchable,
   per module or per function, never globally on by default.

Treating (2) as "counting, but with a bit more data" is the trap: (1) is one
integer increment, (2) means hashing arbitrary Lua values on every call.

## The hard constraint: off must cost nothing

"Wenig oder gar kein Impact" is the requirement that decides the
architecture. There are three candidate shapes, and only one of them
actually satisfies it:

| Approach | Off-cost | Verdict |
|---|---|---|
| `if enabled then count() end` inside every lib function | One boolean check per call, in every function, forever — plus ~250 edited files and a permanent invitation to forget the guard in new code | **Rejected** |
| `debug.sethook` | Fires on every Lua call in the process, not just lib's; catastrophic when on, and the hook itself must be installed to decide | **Rejected** |
| **Wrapper installation at enable time** | **Exactly zero** — no wrapper exists until `start()` runs; `stop()` restores the originals | **Chosen** |

The third is not a new idea in this repo: **`lib.nvim.system.proc_trace`
already does exactly this** for `vim.fn.system`/`vim.system`/`jobstart` —
swap the function, measure, restore on `stop()`. This concept is that same
proven pattern, applied to lib's own surface instead of Neovim's process
APIs, and it should reuse its honest-limits framing too (see below).

**Off-cost is therefore literally zero**: the shipped functions are the
original functions. Not "a nearly-free branch" — the same function object,
byte for byte. That is the strongest possible answer to the requirement, and
it is only achievable because instrumentation is installed rather than
compiled in.

## The constraint nobody expects: `loaded[key]`

`lua/lib/strategies/metatable.lua` caches every resolved key:

```lua
local loaded = {}
setmetatable(LIB, { __index = function(_, key)
  if loaded[key] then return loaded[key] end   -- <-- this
  ...
  loaded[key] = value
  return value
end })
```

Two consequences that shape the whole design:

- **A consumer that already did `local trim = lib.strings.trim` holds the
  raw function.** Wrapping `lib.strings.trim` afterwards does not affect that
  local. Same blind spot `proc_trace` documents for
  `local system = vim.fn.system`. `telemetry.start()` must therefore run as
  early as possible, and the docs must say so plainly rather than implying
  total coverage.
- **Wrapping must invalidate `loaded`**, or the metatable keeps handing out
  the pre-wrap value for keys already touched. This needs a small, explicit
  hook in the strategies (`__telemetry_reset_cache()` or equivalent) — it is
  not something telemetry can do from the outside without reaching into
  another module's local, which it must not do.

Neither of these is a blocker. Both are the kind of thing that, if
discovered during implementation instead of design, produces a module that
silently under-reports and is trusted anyway.

## Proposed API

**Instance-based, not a singleton** — same shape as `logger.new()` and
`docmap.install()`, and for the same reason: this must be usable from any
plugin against its own surface, not only by lib.nvim against `lib.*` (see
[Use from other plugins](#use-from-other-plugins)).

```lua
local telemetry = require("lib.nvim.telemetry")

local t = telemetry.new({ namespace = "lib.nvim" })

t.wrap(lib)               -- instrument a table of functions
t.start()                 -- counting only: the "leave it on for a week" mode

t.start({                 -- counting + argument profiling, scoped
  profile_args = { "fs.find_root", "strings.trim" },
})

t.stop()                  -- restores originals, keeps collected data
t.is_running()

t.report()                -- table, for programmatic use
t.report({ sort = "calls", top = 30 })

t.reset()                 -- clear collected data
t.flush()                 -- persist now (also happens on VimLeavePre)
```

`telemetry.instances()` enumerates every live instance, so one command can
report across all of them without each plugin registering its own.

Plus a user command, following `:LibMap`'s opt-in registration pattern
(`require("lib.nvim.telemetry.command").setup()` — requiring the module
alone never registers a command):

```vim
:LibTelemetry            " report across all instances, in a kit float
:LibTelemetry lsp.nvim   " report for one namespace
:LibTelemetry start
:LibTelemetry stop
:LibTelemetry reset
:LibTelemetry export     " write a JSON snapshot
```

## Scope: whole project, one module, or single functions

Instrumenting everything is rarely what you want, and it is the version with
the highest on-cost. Scope should be selectable at three granularities,
narrowing as you go:

```lua
-- 1. a whole table (a module, or lib's aggregate)
t.wrap(require("lsp.servers"), "servers")

-- 2. only some functions of it
t.wrap(require("lsp.servers"), "servers", { only = { "attach", "detach" } })

-- 3. everything except the noisy internals
t.wrap(require("lsp.handlers"), "handlers", { except = { "on_publish" } })

-- 4. a predicate, when a name list would be a list to maintain
t.wrap(require("lsp.util"), "util", {
  filter = function(name) return not name:match("^_") end,
})

-- 5. a single function, no table involved
t.wrap_fn(require("lsp.servers").attach, "servers.attach")
```

This is not just ergonomics — it is what makes the advice in
[What to instrument](#what-to-instrument-and-what-not-to) actionable.
Saying "don't wrap hot inner helpers, wrap the public surface" is useless
without a mechanism to *express* that, and `only`/`except`/`filter` is that
mechanism. Narrower scope also means less on-cost: the overhead is per
wrapped call, so wrapping 6 functions instead of 120 is proportionally
cheaper while it runs.

`wrap_fn` matters for a different reason: some interesting functions are not
reachable as a named table field (a local passed into a callback, a closure
returned by a factory such as `find_root({...}).find`). Wrapping the value
directly covers those, at the cost of the caller having to store the
returned wrapper themselves.

## Use from other plugins

**Yes — and it should be a first-class use case, not an afterthought.**
`docmap` already set this precedent in this repo: written for `lib.nvim`,
but every layout assumption is an option, so another plugin points it at its
own tree and gets its own map. Telemetry should follow exactly that rule.

```lua
-- in lsp.nvim
local t = require("lib.nvim.telemetry").new({ namespace = "lsp.nvim" })

t.wrap(require("lsp.servers"), "servers")
t.wrap(require("lsp.handlers"), "handlers", { only = { "definition", "hover" } })
t.start()

-- days later, from inside lsp.nvim:
local report = t.report({ since = "7d", top = 20 })
```

Four things make this work, and one of them needs care:

**Persistence is already namespaced.** `cache.disk` keys by namespace, so
`lsp.nvim`'s counts and `lib.nvim`'s counts are separate files with no merge
logic needed. **But**: `cache.disk` builds its path as
`cache_dir .. "/" .. namespace .. ".json"` with *no* sanitization (verified
in `lua/lib/nvim/cache/disk.lua`). A namespace is a plugin-chosen string, so
telemetry must sanitize it before passing it down — otherwise a namespace
containing `/` or `..` writes outside the cache directory. Cheap to fix at
the telemetry layer; fixing it in `cache.disk` itself would be a separate,
wider change.

**Reports are per-instance by default.** `t.report()` returns only that
namespace's data — exactly what "ich aktiviere es in lsp.nvim und kann dort
die stats auslesen" asks for. The cross-instance view is opt-in via
`telemetry.instances()`, so a plugin never accidentally reports on another
plugin's numbers.

**Teardown is per-instance and idempotent.** Each instance restores only
what it wrapped. Stopping twice, or stopping an instance that never started,
is a no-op rather than an error — same rule as `docmap.uninstall()`, and for
the same reason (hot-reloaded configs call setup paths repeatedly).

**The wrap target differs, and that is the real asymmetry.** `lib.nvim` has
one flat aggregate table, so `t.wrap(lib)` covers nearly everything. A
plugin's public surface is usually spread across submodules, so wrapping
`require("lsp")` alone catches far less. Two options, both worth offering:

| Approach | Coverage | Cost |
|---|---|---|
| `t.wrap(module, prefix, opts)`, called per module | Exactly what you list | Explicit, no surprises, but a list to maintain |
| `t.wrap_tree("lsp")` — hook `require` for a module prefix | Everything under the prefix, including lazily-loaded submodules | More invasive; must not break `package.loaded` identity |

Phase 1 should ship `t.wrap()`/`t.wrap_fn()` only. `wrap_tree` is strictly
more powerful and strictly more likely to have surprising interactions — it
deserves its own phase and its own testing, not a day-one bundle.

### The one genuinely tricky case: two instances, one function

If `lsp.nvim`'s instance wraps a function that `lib.nvim`'s instance has
*already* wrapped, you get nested wrappers. Two real problems, not stylistic
ones:

- **Double counting** — the inner wrapper's count and the outer's both fire,
  and neither is wrong on its own, but a naive cross-instance report sums
  them.
- **Restore ordering** — if the *inner* instance stops first, the outer
  wrapper still holds a reference to the inner wrapper, and the "original"
  it restores later is actually a wrapper. Stopping in the wrong order
  leaves instrumentation permanently installed with no way to notice.

For the common case this never happens: each plugin wraps its own modules,
and the sets are disjoint. It only arises when a plugin wants to measure its
use of *another* library's functions — which is really the caller-attribution
feature (extension #2 below), not plain counting.

The fix, when that phase comes: **one shared wrap layer, instances
subscribe.** A function is wrapped at most once, globally; the wrapper
dispatches the event to every instance that registered interest in that key.
Restore then happens once, when the last interested instance detaches, and
double counting is structurally impossible. Phase 1 does not need this, but
the internals must not preclude it — specifically, the wrap bookkeeping
should live in a module-level registry from the start, not inside each
instance's closure.

## Persistence: the "nach 7 Tagen" part

Counting is worthless if it resets every time Neovim restarts, and the
stated use case is explicitly multi-day. `lib.nvim.cache.disk` already does
namespaced JSON persistence with TTL and `pcall`-guarded IO — telemetry
should use it rather than inventing a second file format.

- Flush on `VimLeavePre`, plus a debounced periodic flush (a crash should
  not cost a full session's data).
- Merge on load: a counter is `existing + this_session`, keyed by day so
  `report({ since = "7d" })` is answerable and old days can be dropped.
- Bound the stored size explicitly. An unbounded table keyed by argument
  value is a memory leak with a plausible-sounding name — see below.

## Lifecycle: reminding you to actually read the data

Telemetry that gets switched on and then forgotten is the failure mode this
feature invites: it keeps costing overhead for months, and the data it
collected never gets looked at. So once **enough** data exists, the module
should say so, once, and point at the report.

```
[lib.nvim.telemetry] lsp.nvim has been collecting for 7 days
(48 210 calls, 63 functions). Review with :LibTelemetry lsp.nvim —
stop with :LibTelemetry stop.
```

Design rules, each with a reason:

- **The threshold check must not touch the hot path.** Checking "have we hit
  7 days / N calls yet?" on every wrapped call would add a branch and a
  clock read to the exact code path this whole design keeps minimal. Check
  it where work already happens anyway: at flush time, and once on
  `VimEnter`. A reminder being a few minutes late costs nothing.
- **Fire once per threshold, and persist that it fired.** A reminder that
  reappears every session is a nag that gets muted, which defeats it. The
  "already reminded at 7d" flag belongs in the same cache entry as the
  counts.
- **Both a time and a volume trigger, whichever comes first.** 7 days of a
  barely-used function is not enough data; 50 000 calls in one afternoon
  already is. Configurable per instance: `remind_after = { days = 7,
  calls = 50000 }`, `remind_after = false` to opt out entirely.
- **Actionable, not informational.** The message names the exact commands
  for reading and stopping. A reminder that says "you have data" without
  saying how to look at it just moves the forgetting one step later.
- **Escalate to a second, gentler reminder only if the first is ignored.**
  If collection continues far past the threshold (say 4× the configured
  duration), one more notice — then stop reminding for good. Two messages
  over months is a reminder; more is nagging.

Worth noting: this pairs naturally with the "dominant argument → consider
memoization" hint. The reminder is what gets the user to *look*; the hint is
what makes looking worth it.

## Argument profiling, done honestly

This is the feature with the most ways to go wrong, so it needs the most
explicit rules.

**What to store.** Not the arguments — a *fingerprint*:

- `nil`/boolean/number/short string → the value itself
- long string → truncate with a marker (`"/very/long/pa…" `)
- table → `"<table:n=3>"` (shape, not contents), or an opt-in deep hash for
  a specific function where it is worth the cost
- function/userdata → `"<function>"` / `"<userdata>"`

Storing real argument values means storing file paths, buffer contents,
possibly tokens. A profiler that quietly writes secrets to
`stdpath("cache")` is a security bug, not a feature. Fingerprint by default;
raw values only behind an explicit per-function opt-in that says so.

**Bounded cardinality.** Keep the top N distinct fingerprints per function
(N ≈ 32) plus an `__other` bucket with a count. A function called with 10 000
distinct paths must cost 33 table entries, not 10 000. Without this, the
memory profile depends on user data — the single most likely way this module
becomes the performance problem it was built to find.

**The insight it should produce.** The report should not just dump counts;
it should surface the thing the user actually asked about:

```
lib.nvim.fs.find_root          12 480 calls
  └ 91 %  ("/repo/lib.nvim")           ← dominant argument
  └  6 %  ("/repo/mdview.nvim")
  └  3 %  <other: 47 distinct>
  ⓘ 91 % of calls share one argument — candidate for memoization
     (lib.lua.memo.memo / .lru already exist)
```

That last line is the whole point of the feature. A raw table of numbers
makes the user do the analysis; naming the pattern *and* pointing at the
existing tool (`lib.lua.memo`) is what turns telemetry into a decision.

## What to instrument, and what not to

**Cheap wins, worth it:** anything reached through the `lib` aggregate
(`MODULE_MAP` / `SPECIAL_HANDLERS` — both enumerable, so the wrap list can
be derived rather than hand-maintained; a hand-maintained list is drift
waiting to happen, exactly like the `find_root` type/export mismatch that
`docmap`'s `type-not-exported` check was written for).

**Deliberately not instrumented:**

- Functions called in a *fast event context* (libuv callbacks). A wrapper
  that touches a shared table there is fine, but one that calls `vim.fn.*`
  or `vim.schedule` per call is not. Keep the hot path to: increment
  integer, maybe compute fingerprint. Nothing else. `lib.nvim.fs.mkdirp`
  exists precisely because that context is hostile — telemetry must not
  reintroduce the problem it solved.
- Hot inner helpers where the wrapper genuinely dominates the callee
  (`lib.lua.tables.core` primitives). Instrument the *public* surface;
  wrapping a three-line function to time a three-line function measures the
  wrapper.
- Recursive functions, unless guarded. `find_root`'s chain walk calling
  itself would multiply counts in a way that reads as "hot" when it is not.
  Either count only outermost entries (depth counter) or document the
  behaviour — but pick one deliberately.

## Overhead when it *is* on

Worth stating honestly rather than claiming "negligible":

- Counting only: one table index + one integer add per call. Real, small,
  and constant. Fine to leave on for a week.
- Argument profiling: one fingerprint computation per call. For scalars,
  cheap. For tables, this is where it stops being free — hence the per-
  function opt-in rather than a global switch.
- Timing (if added, see below): two `vim.uv.hrtime()` calls per invocation.

The report should show what mode collected the data, so a week-old dataset
can be read correctly.

## Possible extensions, ranked

Shipped: 1 (timing, `min`/`mean`/`max` — no `p95`, which needs a per-function
histogram and a different size/accuracy trade-off), 3 (coverage, as
`t.coverage()` and `:LibTelemetry coverage`) and 5 (error counting, opt-in).
Not shipped: 2 (caller attribution) and 4 (session comparison) — both are
additive on top of what exists and neither is needed to answer the original
question.

1. **Timing** (`min`/`max`/`mean`/`p95` per function). Natural companion to
   counts and the same machinery. Combined with counts it answers "what
   actually costs time", which is a better optimization question than "what
   is called often".
2. **Caller attribution** — one `debug.getinfo(3, "Sl")` per call to record
   *who* calls a function. Expensive; opt-in per function; but turns
   "`find_root` is called 12 000 times" into "…and 11 000 of them come from
   one autocmd", which is a different fix entirely.
3. **Coverage / dead-surface report** — the inverse question: which exported
   lib functions were called **zero** times in a week. Feeds directly into
   `docmap`'s existing drift checks (an exported, documented, never-used
   function is a maintenance cost). Nearly free: it is the set difference
   between the wrap list and the observed keys.
4. **Session comparison** — diff two snapshots ("before/after this
   refactor"). Cheap once persistence exists.
5. **Error-rate counting** — count `pcall` failures per wrapped function.
   Nearly free, and surfaces "this function is called a lot *and* fails 2 %
   of the time".

## Honest limits (to ship in the module's own docs)

Directly modelled on `proc_trace`'s "HONEST LIMITS" section, because the
same class of blind spot applies and understating it would make the data
misleading:

- Only calls that go **through the wrapped table** are seen. A cached local
  reference taken before `start()` is invisible.
- Direct `require("lib.nvim.fs.mkdirp")` calls bypass the `lib` aggregate
  entirely. Wrapping the aggregate is not the same as wrapping the modules —
  decide explicitly which is instrumented, and say so.
- Counts are per-process. Multiple Neovim instances writing the same cache
  namespace need either merge-on-write or per-instance files.
- Wrapping changes identity: `lib.f == lib.f` still holds, but
  `saved_ref == lib.f` does not after `start()`. Anything comparing function
  identity (unlikely, but it exists) breaks. `stop()` must restore exactly.

## Implementation phases

Phases 1–5 shipped. Phase 6 did not, for the reason stated in it.

1. **Counting + persistence + report**, instance-based, with
   `t.wrap()`/`t.wrap_fn()` and `only`/`except`/`filter` scoping from the
   start. No arg profiling, no timing, no `wrap_tree`. This alone answers
   the original question ("wie oft wurde xy aufgerufen"), works for any
   plugin against its own modules at whatever granularity it wants, and is
   the phase that must have zero off-cost. Scoping belongs in phase 1 rather
   than later: retrofitting it means every early adopter starts with
   "instrument everything", which is the configuration most likely to make
   telemetry itself look expensive.
2. **`:LibTelemetry` command + kit report UI**, including the per-namespace
   form. Uses `lib.nvim.ui.kit`; no new UI code.
3. **Lifecycle reminder** — the time/volume trigger described above. Small,
   and it is what stops phase 1 from quietly running forever unread.
4. **Argument fingerprinting**, per-function opt-in, bounded cardinality,
   plus the "dominant argument → consider memoization" hint.
5. **Timing**, then the extensions above in the listed order.
6. **`wrap_tree(prefix)`** and the shared wrap layer (needed only once two
   instances can target the same function — see the two-instances case
   above). Deliberately last: strictly more power, strictly more ways to
   surprise.

## Open questions

All seven are answered below, each with what shipped and why. They are kept in
their original form because the trade-off is the part worth remembering; the
**Resolved** note is what the code does.

1. **Aggregate vs. modules — for lib.nvim's own instance.** Instrumenting
   `lib.*` (the aggregate) is one wrap site and matches how config code
   calls things. Instrumenting each `require("lib.nvim.…")` module catches
   direct requires too but is ~120 wrap sites and much more invasive. My
   inclination is the aggregate for phase 1, with the limitation documented
   — but this is a real trade-off, not an obvious call. (For *other*
   plugins the question doesn't arise the same way: they list their own
   modules explicitly via `t.wrap()`.)

   > **Resolved: the aggregate**, as `t.wrap_lib()`. The limitation (a direct
   > `require("lib.nvim.fs.mkdirp")` is invisible) is in the module's HONEST
   > LIMITS. The wrap list is *derived* from the strategy rather than
   > hand-written, so it cannot drift; table-valued keys (`lib.strings`,
   > `lib.kit`) get their function fields registered one level deep, since
   > `lib.strings` itself is never called. A plugin wanting module-level
   > coverage calls `t.wrap()` per module, which is what other plugins do
   > anyway.

2. **Where the `loaded` cache hook lives.** Telemetry needs the strategies
   to expose a cache-reset; that is a small public addition to a module that
   currently has none. Worth designing deliberately rather than bolting on.

   > **Resolved: a new `lib.strategies.control`**, which each strategy
   > registers itself with at load time (`keys()` + optional `reset_cache()`).
   > It answers a second question the concept did not raise but which turned
   > out to matter more: under the metatable strategy `pairs(lib)` yields
   > *nothing*, so the wrap list was not discoverable at all. `keys()` falls
   > back to `pairs()` for the plain "eager"/"lazy" tables, so nothing depends
   > on registration having happened.
   >
   > Note on `loaded[key]`: `wrap_lib()` `rawset`s the wrapper onto the
   > aggregate, and a raw field shadows `__index` entirely — so the resolved-key
   > cache cannot hand out a pre-wrap value for a wrapped key. `reset_cache()`
   > is still used on `unwrap()`, where the raw fields are removed and the
   > metatable takes over again.

3. **Day-bucketing granularity.** Per-day keys make "last 7 days" trivial
   and bound growth. Per-session keys answer "which session was slow" but
   grow unboundedly. Probably per-day, with a session counter alongside.

   > **Resolved: per-day, with a session counter**, as leaned. Day buckets hold
   > call counts only — argument, timing and error stats are lifetime totals, so
   > the stored size does not multiply by the retention window. The clock is
   > read once per flush rather than per call, which costs at most one flush
   > interval of misattribution around midnight and keeps the hot path free of
   > `os.date`.

4. **Default retention.** 7 days matches the stated use case; 30 would
   support "did last month's refactor change anything". Needs a number, and
   a documented prune step.

   > **Resolved: 30 days** (`retention_days`), pruned on every flush. 7 days is
   > the *reminder* threshold, which is the number the use case actually named;
   > retention only has to be at least as long, and 30 is what makes
   > before/after-a-refactor answerable without a second mechanism.

5. **Namespace collision between plugins.** Two plugins picking the same
   namespace silently share a cache file and produce merged, wrong numbers.
   Options: require the namespace to match the plugin's own module prefix,
   warn on a second `new()` with an existing namespace, or just document it.
   Leaning "warn" — it is cheap and the failure is otherwise invisible.

   > **Resolved: warn**, as leaned. Requiring the namespace to match a module
   > prefix would break the legitimate case of one plugin running several
   > scoped instances. Separately, the namespace is **sanitized** before it
   > reaches `cache.disk` — the unescaped-path hole this document flagged is
   > closed at the telemetry layer, and `store.sanitize` is covered by the spec.

6. **Should a plugin's instance auto-stop on `VimLeavePre`?** Flushing there
   is settled; whether to also restore the wrappers is not. It costs
   nothing either way at shutdown, but "stop() always runs" is a cleaner
   invariant to reason about than "sometimes the process just ends".

   > **Resolved: flush only, no auto-stop.** The invariant `stop()` protects is
   > "no wrapper outlives the decision to collect", and at `VimLeavePre` the
   > process outlives nothing. Calling `stop()` there would also make the exit
   > path do teardown work whose only observable effect is on state about to be
   > discarded. `stop()` itself flushes, so the two paths converge on the part
   > that matters.

7. **Should `only`/`except` accept patterns, or exact names only?** Exact
   names are unambiguous; Lua patterns are far more convenient for "all
   public functions" (`filter` already covers that case, which may make
   patterns redundant). Leaning exact names plus `filter`, so there is one
   escape hatch rather than two overlapping ones.

   > **Resolved: exact names plus `filter`**, as leaned. `filter` receives
   > `(name, fn)`, so a pattern is one line and anything a pattern cannot
   > express is available too.

## What shipped beyond the concept

Three things the design did not call for, each because implementing it exposed
the need:

- **The shared wrap layer is in phase 1, not phase 6.** The concept deferred it
  on the grounds that phase 1 only needed the *bookkeeping* to be module-level.
  It turned out that once bookkeeping is module-level, subscription is a handful
  of extra lines — and shipping the nesting bug first, then fixing it later,
  would mean early data collected under it is quietly wrong.
- **The dominant-argument hint is suppressed below 20 calls and for
  zero-argument calls.** `()` is always 100 % dominant and never actionable, and
  3-of-4 calls is 75 % and means nothing. A hint that fires on noise is a hint
  that gets ignored, which costs more than not having it.
- **`errors` and `outermost_only` are separate opt-ins from timing**, because
  both need the call to return through the wrapper even when it raises — that
  is a `pcall` per call, a materially different cost from two `hrtime()` reads,
  and bundling them would have made timing quietly expensive.


