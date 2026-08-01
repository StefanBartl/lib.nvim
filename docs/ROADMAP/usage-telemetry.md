# `lib.nvim.telemetry` — opt-in call tracing & usage statistics

> **Status:** concept, not implemented. Written in response to: "ein Modul,
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

```lua
local telemetry = require("lib.nvim.telemetry")

-- Counting only. This is the "leave it on for a week" mode.
telemetry.start()

-- Counting + argument profiling, scoped. Never global by default.
telemetry.start({
  profile_args = { "lib.nvim.fs.find_root", "lib.lua.strings.trim" },
})

telemetry.stop()          -- restores originals, keeps collected data
telemetry.is_running()

telemetry.report()        -- table, for programmatic use
telemetry.report({ sort = "calls", top = 30 })

telemetry.reset()         -- clear collected data
telemetry.flush()         -- persist now (also happens on VimLeavePre)
```

Plus a user command, following `:LibMap`'s opt-in registration pattern
(`require("lib.nvim.telemetry.command").setup()` — requiring the module
alone never registers a command):

```vim
:LibTelemetry            " show the report in a kit float
:LibTelemetry start
:LibTelemetry stop
:LibTelemetry reset
:LibTelemetry export     " write a JSON snapshot
```

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

1. **Counting + persistence + report.** No arg profiling, no timing. This
   alone answers the original question ("wie oft wurde xy aufgerufen") and
   is the phase that must have zero off-cost.
2. **`:LibTelemetry` command + kit report UI.** Uses `lib.nvim.ui.kit`; no
   new UI code.
3. **Argument fingerprinting**, per-function opt-in, bounded cardinality,
   plus the "dominant argument → consider memoization" hint.
4. **Timing**, then the extensions above in the listed order.

## Open questions

1. **Aggregate vs. modules.** Instrumenting `lib.*` (the aggregate) is one
   wrap site and matches how config code calls things. Instrumenting each
   `require("lib.nvim.…")` module catches direct requires too but is ~120
   wrap sites and much more invasive. My inclination is the aggregate for
   phase 1, with the limitation documented — but this is a real trade-off,
   not an obvious call.
2. **Where the `loaded` cache hook lives.** Telemetry needs the strategies
   to expose a cache-reset; that is a small public addition to a module that
   currently has none. Worth designing deliberately rather than bolting on.
3. **Day-bucketing granularity.** Per-day keys make "last 7 days" trivial
   and bound growth. Per-session keys answer "which session was slow" but
   grow unboundedly. Probably per-day, with a session counter alongside.
4. **Default retention.** 7 days matches the stated use case; 30 would
   support "did last month's refactor change anything". Needs a number, and
   a documented prune step.
