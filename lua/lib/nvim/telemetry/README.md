# `lib.nvim.telemetry`

Opt-in call counting and usage statistics. Answers *"how often was
`lib.strings.trim` called in the last 7 days, and with what arguments?"* — and,
when one argument dominates, says so and points at `lib.lua.memo`.

Counts survive restarts (`lib.nvim.cache.disk`, namespaced per plugin), which is
the whole point: the interesting question is asked days after collection
started.

```lua
local telemetry = require("lib.nvim.telemetry")

local t = telemetry.new({ namespace = "lib.nvim" })
t.wrap_lib()      -- or: t.wrap(require("my.module"), "module")
t.start()         -- counting only: the leave-it-on-for-a-week mode

-- days later
vim.print(t.report({ since = "7d", top = 20 }))
```

## Off costs nothing — literally

Instrumentation is **installed**, not compiled in. Until `start()` runs, the
shipped functions *are* the original functions — the same objects, not a
"nearly-free branch" — and `stop()` puts them back. That is why there is no
`if enabled then count() end` scattered through ~250 files, and why
`debug.sethook` (which fires on every Lua call in the process) was never an
option. Same pattern [`lib.nvim.system.proc_trace`](../system/README.md)
already uses for `vim.fn.system`.

When it *is* on:

| Mode | Per-call cost |
| --- | --- |
| Counting | one table index + one integer add |
| Timing | + two `vim.uv.hrtime()` reads |
| Argument profiling | + one fingerprint computation (cheap for scalars, not for tables) |
| `errors` / `outermost_only` | + one `pcall` (the call must return through us even when it raises) |

Argument profiling is per-function opt-in rather than a global switch for
exactly this reason.

## API

### `telemetry.new(opts)` → instance

Instance-based, not a singleton — same shape as `logger.new()`, and for the same
reason: any plugin must be able to point one at its own surface with its own
persisted counts.

| Option | Default | Meaning |
| --- | --- | --- |
| `namespace` | `"unnamed"` | required in practice; also the on-disk cache key |
| `dir` | `stdpath("cache")/lib.nvim/cache` | cache directory override |
| `retention_days` | `30` | day buckets older than this are pruned on flush |
| `flush_interval_ms` | `60000` | debounced periodic flush; `0` disables |
| `remind_after` | `{ days = 7, calls = 50000 }` | lifecycle reminder; `false` opts out |
| `persist` | `true` | `false` keeps everything in memory |
| `max_arg_values` | `32` | distinct fingerprints kept per function |

A second `new()` with a namespace that already has a live instance **warns** —
two plugins sharing a namespace would silently merge into one cache file and
produce wrong numbers, and that failure is otherwise invisible.

### Scope — whole table, some functions, or one function

Instrumenting everything is rarely what you want and is the version with the
highest on-cost. Scope narrows at four granularities:

```lua
t.wrap(require("lsp.servers"), "servers")                                  -- a whole module
t.wrap(require("lsp.servers"), "servers", { only = { "attach", "detach" } })
t.wrap(require("lsp.handlers"), "handlers", { except = { "on_publish" } })
t.wrap(require("lsp.util"), "util", {                                      -- a predicate
  filter = function(name) return not name:match("^_") end,
})

local traced = t.wrap_fn(factory().find, "find_root.find")                 -- a bare function
```

`only` / `except` take **exact names**, never patterns; `filter` is the single
escape hatch, rather than two overlapping mechanisms each needing their own
edge cases explained.

`wrap_fn` exists because some interesting functions are not reachable as a named
table field (a closure returned by a factory, a callback held in a local). It
returns a stable dispatcher you must store and call in place of the original —
that indirection is what lets `start()`/`stop()` toggle instrumentation without
your saved reference going stale.

`t.wrap_lib()` instruments the `require("lib")` aggregate. Its key set is
*derived* from the strategy (see [`lib.strategies.control`](../../strategies/control.lua))
rather than hand-maintained — a hand-written list is drift waiting to happen.
Table-valued keys (`lib.strings`, `lib.kit`, …) get their function fields
registered one level deep.

### Lifecycle

```lua
t.start()                                  -- counting only
t.start({ profile_args = { "fs.find_root" },  -- or `true` for everything
          time = { "fs.find_root" },
          errors = true })
t.stop()                                   -- restores originals, keeps the data
t.is_running()
t.unwrap()                                 -- also forget the registered targets
```

`stop()` is idempotent — a second `stop()`, or one on an instance that never
started, is a no-op rather than an error, because hot-reloaded configs call
setup paths repeatedly.

### Reading the data

```lua
t.report({ sort = "calls", top = 30, since = "7d" })  -- table
t.lines({ top = 20 })                                 -- rendered strings
t.coverage()                                          -- { called, uncalled }
t.reset()                                             -- clear memory + disk
t.flush()                                             -- persist now
```

`sort` is `"calls"` (default), `"name"` or `"time"`. `since` accepts `"7d"`,
`"24h"`, `"2w"` or a bare day count and is answered from the per-day buckets.

`coverage()` is the inverse question: which registered functions were called
**zero** times. An exported, documented, never-used function is a maintenance
cost.

Module level:

```lua
telemetry.instances()        -- every live instance
telemetry.get("lsp.nvim")
telemetry.report_all(opts)
telemetry.flush_all()
telemetry.stop_all()
```

## `:LibTelemetry`

Opt-in, like `:LibLogger` — requiring the module registers nothing:

```lua
require("lib.nvim.telemetry.command").setup()
```

```vim
:LibTelemetry                 " report across every live instance, in a kit float
:LibTelemetry lsp.nvim        " report for one namespace
:LibTelemetry start [ns]      " every instance, or just one
:LibTelemetry stop [ns]       " every instance, or just one
:LibTelemetry reset [ns]      " every instance, or just one
:LibTelemetry coverage
:LibTelemetry export [path]
```

`start`/`stop`/`reset` take an optional namespace — `:LibTelemetry stop
markdown.nvim` steers just that instance, leaving every other one running.
Omit it to act on every instance at once. `<Tab>` after `start `/`stop `/
`reset ` completes namespaces only (not the subcommand list again).

## Use from another plugin

A first-class use case, not an afterthought — `docmap` set the precedent in this
repo: written for lib.nvim, but every layout assumption is an option.

```lua
local t = require("lib.nvim.telemetry").new({ namespace = "lsp.nvim" })

t.wrap(require("lsp.servers"), "servers")
t.wrap(require("lsp.handlers"), "handlers", { only = { "definition", "hover" } })
t.start()

-- days later, from inside lsp.nvim:
local report = t.report({ since = "7d", top = 20 })
```

Four things make this work:

- **Persistence is namespaced.** `lsp.nvim`'s counts and `lib.nvim`'s counts are
  separate files with no merge logic. The namespace is **sanitized** before it
  reaches `cache.disk`, which builds its path as `dir .. "/" .. namespace ..
  ".json"` with no escaping — a namespace containing `/` or `..` would otherwise
  write outside the cache directory.
- **Reports are per-instance by default.** The cross-instance view is opt-in via
  `telemetry.instances()`, so a plugin never accidentally reports on another
  plugin's numbers.
- **Teardown is per-instance and idempotent.** Each instance restores only what
  it wrapped.
- **Two instances can share a function safely.** A function is wrapped at most
  once, globally; instances subscribe to the one wrapper
  ([`registry.lua`](registry.lua)). Nesting wrappers would double-count and, if
  the *inner* instance stopped first, leave the outer one holding a wrapper it
  would later reinstall as "the original" — instrumentation permanently on with
  nothing to notice it. Restore happens when the last subscriber detaches.

## Argument profiling, done honestly

What is stored is a **fingerprint**, never the arguments:

| Value | Stored as |
| --- | --- |
| `nil` / boolean / number / short string | the value itself |
| long string | truncated with an ellipsis marker |
| table | `<table:#3>` / `<table:map>` — shape, not contents |
| function / userdata / thread | `<function>` / `<userdata>` / `<thread>` |

Storing real argument values would mean writing file paths, buffer contents and
possibly tokens into `stdpath("cache")`. A profiler that quietly does that is a
security bug, not a feature.

**Cardinality is bounded.** The top `max_arg_values` (32) distinct fingerprints
are kept per function, plus an "other" bucket with a count and an honest
`distinct` total. A function called with 10 000 distinct paths costs 33 entries,
not 10 000 — otherwise the memory profile is a function of user data, which is
the most likely way this module becomes the performance problem it was built to
find.

The output names the pattern rather than leaving you to spot it:

```
fs.find_root                12 480 calls
    └  91 %  ("/repo/lib.nvim")
    └   6 %  ("/repo/mdview.nvim")
    └   3 %  <other: 47 distinct>
    ⓘ 91 % of calls share one argument — candidate for memoization (lib.lua.memo.memo / .lru)
```

The hint is suppressed below 20 calls and for zero-argument calls (`()` is
always 100 % dominant and never actionable).

## Lifecycle reminder

Telemetry that gets switched on and forgotten is the failure mode this feature
invites. Once enough data exists the module says so — **once** — and says it
actionably:

```
[lib.nvim.telemetry] lsp.nvim has been collecting for 7 day(s)
(48210 calls, 63 functions). Review with :LibTelemetry lsp.nvim —
stop with :LibTelemetry stop.
```

- Checked at flush time and once on `VimEnter`, **never on the hot path**. A
  reminder a few minutes late costs nothing; a clock read per wrapped call costs
  exactly what this design avoids.
- Fires once and persists that it fired, in the same cache entry as the counts.
  A reminder that reappears every session is a nag, and a nag gets muted.
- Both a time and a volume trigger, whichever comes first — 7 days of a
  barely-used function is not enough data; 50 000 calls in one afternoon is.
- Escalates once at 4× the configured duration, then stops for good.

## What to instrument, and what not to

**Deliberately not instrumented:**

- Functions called in a **fast event context** (libuv callbacks). The hot path
  here stays at "increment an integer, maybe compute a fingerprint" precisely so
  a wrapper is safe there — but `lib.nvim.fs.mkdirp` exists because that context
  is hostile, and telemetry must not reintroduce the problem it solved.
- **Hot inner helpers** where the wrapper dominates the callee
  (`lib.lua.tables.core` primitives). Wrapping a three-line function to measure a
  three-line function measures the wrapper. Instrument the *public* surface.
- **Recursive functions**, unless you decide what you want: every entry is
  counted by default (documented, not accidental); `{ outermost_only = true }`
  collapses a recursive chain to one count, at the cost of a `pcall` per call.

## Honest limits

- Only calls that go **through the wrapped table** are seen. A consumer that did
  `local trim = lib.strings.trim` before `start()` holds the raw function and is
  invisible. Start as early as possible. (Same blind spot `proc_trace` documents
  for `local system = vim.fn.system`.)
- `wrap_lib()` instruments the aggregate. A direct
  `require("lib.nvim.fs.mkdirp")` bypasses it entirely — wrap the module itself
  if you need those calls counted.
- Counts are per-process, but every flush **re-reads and merges** what is on
  disk, so two Neovim instances sharing a namespace add up rather than clobber
  each other.
- Wrapping changes identity: after `start()`, a reference saved earlier is no
  longer `==` the table's current value. `stop()` restores exactly.
- Day bucketing reads the clock once per flush, not per call, so calls in the
  last flush interval before midnight land in the previous day.
- Timing reports `min`/`mean`/`max`. No `p95` — that needs a histogram per
  function, which is a different size/accuracy trade-off than this module makes.

## Not implemented

`wrap_tree(prefix)` — hooking `require` so lazily-loaded submodules are caught
automatically (phase 6 of [the roadmap](../../../../docs/ROADMAP/usage-telemetry.md)).
Strictly more powerful and strictly more ways to surprise, notably around
`package.loaded` identity. Use explicit `wrap()` calls per module.

## Files

| File | Role |
| --- | --- |
| `init.lua` | instance factory, scoping, lifecycle, module-level registry |
| `registry.lua` | the one shared wrap layer; instances subscribe to a site |
| `store.lua` | persistence, namespace sanitization, merge-on-write, day buckets, pruning |
| `fingerprint.lua` | argument → bounded, non-secret string key |
| `report.lua` | report building + rendering, incl. the memoization hint |
| `reminder.lua` | the time/volume lifecycle trigger |
| `command.lua` | `:LibTelemetry` (opt-in `setup()`) |
