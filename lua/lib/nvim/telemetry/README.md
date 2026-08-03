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

| Mode | Per-call cost | Measured (200k calls, 2 scalar args) |
| --- | --- | ---: |
| Counting | one table index + one integer add | **0.014 µs** |
| + timing | two `vim.uv.hrtime()` reads | 0.394 µs |
| + argument profiling | one fingerprint computation | 0.619 µs |
| `errors` / `outermost_only` | one `pcall` (the call must return through us even when it raises) | — |

Counting is genuinely free at editor scale. Argument profiling is **~44×
counting** — still nothing on a surface driven by keypresses and autocmds
(0.6 µs × a few thousand calls a day), and a real cost on helpers that run in
inner loops. That asymmetry is why it is opt-in per function rather than a
global switch, and why `profile_args` accepts a predicate:

```lua
t.start({ profile_args = function(key) return key:match("^bindings%.") ~= nil end })
```

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
| `report_file` | `false` | keep this namespace's Markdown report on disk, rewritten at every flush — see "Browser report" |
| `info` | `{}` | free-form metadata bundled with the report (branch, version, …) — see "Report metadata" below |

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

### `wrap_loaded` — a whole plugin, not just its façade

Wrapping one module usually measures the wrong thing. A plugin's `init.lua`
is typically a thin façade over the modules that hold the real code —
`require("markdown")` exposes **11** one-line delegators while the 35 loaded
`markdown.*` modules hold **125** functions, and the ones its keymaps actually
call live only in the latter.

```lua
t.wrap_loaded("markdown")                       -- the whole loaded subtree
t.wrap_loaded("markdown", {
  module_only   = { "markdown.bindings.actions" },   -- exact module names
  module_except = { "markdown.config" },
  module_filter = function(name)                     -- predicate over the path
    return not name:find("@types", 1, true)
  end,
  only = { "attach" },                               -- per-function scoping
})                                                   -- still applies underneath
```

Module-level scoping uses the same `only`/`except`/`filter` vocabulary as the
per-function scoping, one level up, so there is one thing to learn rather than
two. Both apply: modules are selected first, then functions within them.

Keys are the module path minus the prefix, plus the function name —
`markdown.bindings.actions.next_heading` → `bindings.actions.next_heading`.
The namespace already says which plugin this is.

**Why "loaded" and not "every module on disk":** discovering submodules by
scanning `lua/` would mean `require`-ing every file to see what is in it,
forcing eager loading of modules the plugin deliberately deferred and running
their top-level code as a side effect of counting. Reading `package.loaded`
costs nothing and cannot break a lazy-loading plugin. The trade-off is that
coverage is *"what is loaded at this moment"* — call it after the plugin has
initialized, and call it again later to pick up modules required since
(re-registering an existing target is a no-op, so nothing double-counts).

### Lifecycle

```lua
t.start()                                  -- counting only
t.start({ profile_args = { "fs.find_root" },  -- a key list,
          time = true,                        -- `true` for everything,
          errors = function(key)              -- or a predicate over the key
            return key:match("^io%.") ~= nil
          end })
t.stop()                                   -- restores originals, keeps the data
t.is_running()
t.unwrap()                                 -- also forget the registered targets
```

`stop()` is idempotent — a second `stop()`, or one on an instance that never
started, is a no-op rather than an error, because hot-reloaded configs call
setup paths repeatedly.

### Persistent enable/disable

`stop()` only affects the current process — tomorrow's session calls
`t.start()` again and it's back. For "I looked at `markdown.nvim`'s numbers,
I'm done, stop wrapping it, and don't start it again next time either" without
editing whoever calls `t.start()` at startup:

```lua
telemetry.disable("markdown.nvim")   -- persists; stops a live instance right now
telemetry.enable("markdown.nvim")    -- clears it; resumes a live instance right now
telemetry.is_disabled("markdown.nvim")
telemetry.disabled()                 -- every namespace currently disabled
```

Or from the command line: `:LibTelemetry disable markdown.nvim` /
`:LibTelemetry enable markdown.nvim` / `:LibTelemetry disabled`. Works even
before that namespace's instance has ever been created (disable a plugin
before it loads this session) — `inst.start()` checks the flag and is a
no-op while it's set, so the caller that wires `t.start()` up once at startup
never has to change. The flag lives in its own cache entry, separate from a
namespace's collected data, so `t.reset()` clears counts without silently
re-enabling anything.

One documented edge: the flag is persisted under the instance's own
`opts.dir` once that instance exists (so it's checked consistently), but
falls back to the default cache dir when disabling a namespace that has no
live instance yet. If that instance later shows up with a **custom** `dir`,
disable it again after it's created rather than before.

### Reading the data

```lua
t.report({ sort = "calls", top = 30, since = "7d" })  -- table
t.lines({ top = 20 })                                 -- rendered strings
t.coverage()                                          -- { called, uncalled }
t.resolved_modules()                                  -- { [key] = real Lua module path }
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

### Report metadata — which branch/version this data came from

A count on its own does not say *when* it is from — 12,000 calls to a
function that no longer exists by that name a week later is a stale number
wearing a fresh-looking one's clothes. `Options.info` bundles whatever the
caller considers the important context alongside the counts:

```lua
telemetry.new({
  namespace = "lsp.nvim",
  info = { branch = "main", version = "v1.2.3" },  -- any string keys, any string values
})
```

This module never inspects a repo to guess at that — the caller almost
always already knows which directory its own plugin lives in, and guessing
wrong silently is worse than not having the field. `lib.nvim.git.info(dir)`
is a ready-made source for the common case:

```lua
local info = require("lib.nvim.git").info(plugin_dir)
-- { branch = "main", version = "v1.2.3" or a short hash if untagged, commit = "abc1234" }
telemetry.new({ namespace = "lsp.nvim", info = info })
```

Shows up in `t.report().info`, and as a line in both `t.lines()` and
`t.markdown()` (sorted by key, so rendering is deterministic) — absent
entirely when empty, rather than an empty line nobody asked for.

**Last-write-wins, not merged field-by-field.** A branch switch between
sessions replaces the whole `info` table on the next flush; the previous
session's fields do not linger alongside the new ones the way `wrap_loaded()`
keys or counts accumulate. `Options.info` is set once at construction
(`telemetry.new`) — there is no `t.set_info(...)` to change it mid-process,
the same way `dir`/`persist` are construction-time only.

### Reading without an instance — and resolving keys to real modules

A fresh Neovim process with no live instance for a namespace (a `:DocMap
check` run, a CLI tool, a health check) can still read what an *earlier*
session collected:

```lua
local data = telemetry.load("lsp.nvim")   -- Lib.Telemetry.Data|nil
if data then
  vim.print(data.functions)   -- same shape as t.report() works from
end
```

`nil` means *nothing was ever persisted for this namespace* — deliberately
distinct from a well-formed empty table. A caller has to be able to tell
"telemetry was never enabled here" from "enabled, and zero calls happened",
or an unanalyzed tree renders as a graveyard instead of "no data".

The other half of "read this from outside the process that collected it" is
matching a telemetry key back to the real Lua module it came from — the key
alone (`"bindings.actions.next_heading"`) does not say that. `wrap_loaded()`
knows the answer at wrap time (its keys ARE derived from a real
`package.loaded` path) and records it automatically:

```lua
t.wrap_loaded("markdown")
t.resolved_modules()   -- { ["bindings.actions.next_heading"] = "markdown.bindings.actions", ... }
```

The same map is in `data.modules` from `telemetry.load()`, keyed the same
way — no live instance required to read it either. A plain `t.wrap(container,
prefix)` resolves nothing on its own (`prefix` is a caller-chosen label, not
necessarily a real module path — `t.wrap(require("lsp.servers"), "servers")`
does not make `"servers"` mean `"lsp.servers"`), unless the caller vouches
for it explicitly:

```lua
t.wrap(require("lsp.servers"), "servers", { module_id = "lsp.servers" })
```

A key with no entry in `resolved_modules()` / `data.modules` is **unmatched**,
not "zero calls" — a consumer joining telemetry against a static key set (the
motivating case: documentation.nvim's `dead-function` check, see
[`telemetry-documentation-bridge.md`](../../../../docs/ROADMAP/telemetry-documentation-bridge.md))
must keep those two claims distinguishable, or the join produces false
positives it can't tell apart from real ones.

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
:LibTelemetry export [path]   " JSON, or Markdown if path ends .md
:LibTelemetry open [ns]       " render + open externally — see "Browser report" below
```

`start`/`stop`/`reset`/`open` take an optional namespace — `:LibTelemetry stop
markdown.nvim` steers just that instance, leaving every other one running.
Omit it to act on every instance at once. `<Tab>` after `start `/`stop `/
`reset `/`open ` completes namespaces only (not the subcommand list again).

`export`'s format is inferred from the target path's own extension rather
than a separate flag — this command's argument parsing stays positional
throughout. `:LibTelemetry export report.md` writes the same document
`telemetry.markdown_all()` would; anything else (including the default
auto-named path) writes the existing JSON snapshot.

## Browser report

Two separable things: rendering a report as **Markdown** (useful on its own —
paste into an issue, commit a snapshot, diff two weeks), and handing that
Markdown to a **browser** via [mdview.nvim](https://github.com/StefanBartl/mdview.nvim)'s
own `:MDView standalone`, which already does exactly the right thing for
this: it hands a file path to the relay binary's own `--watch` mode and steps
out of the chain entirely — the relay watches the file on disk and
broadcasts changes to the browser itself. mdview.nvim is a soft dependency
throughout, `pcall`-guarded.

```lua
t.markdown({ since = "7d", top = 30 })   -- -> string[], the same shape as t.lines() but GFM
telemetry.markdown_all(opts)             -- every instance, one combined document
```

**Self-updating, opt-in:** `report_file = true` keeps a namespace's Markdown
report on disk (`stdpath("cache")/lib.nvim/telemetry/<namespace>.md`),
rewritten at every flush. Point `:MDView standalone` at that same path (or
just use `:LibTelemetry open <ns>`) and the browser tab becomes a live
dashboard with no new machinery on either side — telemetry already flushes
periodically, mdview's relay already watches a file. Writing a Markdown file
every 60 s for someone who never opened a browser is waste, so this is opt-in
per instance:

```lua
telemetry.new({ namespace = "lib.nvim", report_file = true })
```

**`:LibTelemetry open [ns]`** renders + opens externally, forcing a flush
first so the render is current. Which renderer it uses is configuration, not
a subcommand — the same shape `lib.nvim.progress` already uses for its
`progress_style`:

```lua
require("lib.nvim.telemetry").setup({
  report_style = "auto",   -- "auto" | "kit" | "mdview" | "file"
})
```

| Style | Effect |
| --- | --- |
| `"auto"` (default) | mdview if loadable, else the kit float |
| `"kit"` | the same in-editor float `:LibTelemetry <ns>` already renders |
| `"mdview"` | write the report + `:MDView standalone` it; falls back to `"kit"` if mdview is not loadable |
| `"file"` | just write the report to disk, no window opened |

This is module-level, not per-instance (`telemetry.setup`, not
`telemetry.new({...})`) — `:LibTelemetry open` with no namespace spans every
live instance at once, so there is one resolved answer to "how should `open`
render", not one per instance.

Honest limits:

- **The browser shows the last flush, not this instant.** `open` forces one,
  so the initial render is current; after that it is as live as
  `flush_interval_ms`.
- **A bare `:LibTelemetry open` (no namespace) is a snapshot, not
  self-updating.** Only a per-namespace file has one flush cycle that owns
  it; the combined `report.md` has no single instance to keep rewriting it,
  so it is rendered fresh at invocation time and left there.
- **No HTML of our own.** Markdown out, mdview renders — generating HTML here
  would duplicate mdview's themes/highlighter and immediately drift from them.
- **mdview.nvim self-installs its relay binary from GitHub Releases on first
  use** (checksum-verified, no Go/Rust toolchain needed) — for *either* of
  its modes, not just standalone. The first `:LibTelemetry open` with
  `report_style = "mdview"` may pause briefly for that download; failures
  (no network, no `curl`) are mdview's own to report, and this bridge just
  degrades to `"kit"`.

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
automatically. Deliberately last: strictly more powerful and strictly more
ways to surprise, notably around `package.loaded` identity. Use explicit
`wrap()` calls per module.

## Files

| File | Role |
| --- | --- |
| `init.lua` | instance factory, scoping, lifecycle, module-level registry |
| `registry.lua` | the one shared wrap layer; instances subscribe to a site |
| `store.lua` | persistence, namespace sanitization, merge-on-write, day buckets, pruning, module-id map, read-without-an-instance |
| `fingerprint.lua` | argument → bounded, non-secret string key |
| `report.lua` | report building + rendering (terminal lines and Markdown), incl. the memoization hint |
| `report_file.lua` | where a rendered Markdown report lives on disk, and writing one there |
| `report_style.lua` | resolve `report_style` ("auto"/"kit"/"mdview"/"file") to a concrete destination |
| `renderers/mdview.lua` | bridges a report to a browser tab via mdview.nvim's `:MDView standalone` |
| `config.lua` | module-level defaults (`report_style`) via `telemetry.setup()` |
| `reminder.lua` | the time/volume lifecycle trigger |
| `toggle.lua` | persistent per-namespace enable/disable, independent of an instance's own data |
| `command.lua` | `:LibTelemetry` (opt-in `setup()`) |
