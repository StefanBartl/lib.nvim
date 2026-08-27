# `lib.nvim.bindings.autocmd.dispatcher`

One autocmd, many handlers — a generic, event-agnostic dispatcher factory,
plus a `FileType` convenience wrapper on top.

This README covers the full reasoning, including why this is **not** a
performance win over plain autocmds for the common case — it genuinely does
more work per event than native dispatch, and the honest reasons to reach
for it anyway (uniform lazy-loading, deterministic `priority` ordering,
per-buffer `once`).

## What it costs — measured

The paragraph above says this does more work per event than native dispatch.
Here is how much, so the decision is a number and not a feeling.

**Caveat first:** one machine (Windows 11, LuaJIT, Neovim run with `--clean`),
one synthetic benchmark, 2000 events per sample, median of 5 runs. Treat the
*shape* as the finding and the absolute microseconds as indicative. The script
is `docs/ROADMAP/tools/autocmd_dispatch_bench.lua` in the author's config repo;
it is short enough to re-run wherever it matters.

Two cases differ, and only one of them matters:

- **hit** — the event carries a key that has handlers. Both variants must run
  them.
- **miss** — the event carries a key that has none. A native autocmd with a
  `pattern` is filtered in C and never enters Lua; this dispatcher always does.

| handlers | native hit | dispatcher hit | native **miss** | dispatcher **miss** |
| ---: | ---: | ---: | ---: | ---: |
| 1  | 32.9 µs | 31.1 µs | **0.9 µs** | **30.9 µs** |
| 5  | 31.4 µs | 29.2 µs | 2.0 µs | 29.5 µs |
| 20 | 40.0 µs | 30.1 µs | 6.3 µs | 30.0 µs |
| 50 | 52.6 µs | 32.3 µs | 14.0 µs | 30.0 µs |

### The control measurement, which is the actual finding

Read alone, "33× slower on a miss" sounds like this module is expensive. It is
not. The same benchmark, with no dispatcher involved at all:

| | per event |
| --- | ---: |
| no autocmd registered | 0.23 µs |
| 1 autocmd, pattern does **not** match (filtered in C) | 0.96 µs |
| 1 autocmd, **empty** Lua callback runs | **29.0 µs** |

Entering Lua costs ~29 µs. That is the entire difference. The dispatcher's own
work — one `key(ev)` call, one cached table lookup, an early return — is the
0.9 µs between 29.0 and 30.9.

So the honest statement is not "the dispatcher is slow". It is: **a native
autocmd that does not match never enters Lua, and this one always does.**

### Reading the table

- **Misses cost a flat ~30 µs**, whatever the handler count. Native costs
  ~0.3 µs per *registered* autocmd on that event, so the two meet at roughly
  100 autocmds on one event.
- **Hits are a wash below ~20 handlers**, and the dispatcher pulls ahead above
  that: Neovim pays its ~29 µs Lua entry once either way, but native also walks
  and pattern-checks every registered autocmd.

### Is 30 µs a problem?

For anything firing at human speed — `BufEnter`, `FileType`, `BufWritePost` —
no, by orders of magnitude. Fifty buffer switches a minute with ten handlers
costs about 1.4 ms *per minute*.

For continuously firing events — `CursorMoved`, `TextChangedI` — the cost is
paid unconditionally where native pays almost nothing. Even there the arithmetic
stays small: 200 events per second, a rate you only reach by holding a key down,
is 6 ms/s, i.e. well under one percent. An editor is not a game loop, and there
is no frame budget to blow.

The conclusion the author drew, and it is a judgement rather than a
measurement: the flat cost is small enough that it should not decide anything.
Choose this module for what it actually gives you — deterministic ordering,
uniform lazy-loading, per-buffer `once` — and not against it for a number you
will never perceive.

## Usage

```lua
local dispatcher = require("lib.nvim.bindings.autocmd.dispatcher")

local ft = dispatcher.new({
  event = "FileType",
  group = "MyFiletypeDispatcher",
  key = function(ev) return ev.match end,
})

ft.register("lua", {
  load = function() require("lsp.languages.scripting.lua") end,
  priority = 10,
  once = true,          -- per buffer, not once-globally
})

ft.register({ "c", "cpp" }, { load = function() require("lsp.languages.systems.c") end })
ft.register("noice*", { load = function() require("noice_setup") end })  -- glob key

-- A handler can also be a plain function, called directly with ctx:
ft.register("markdown", function(ctx)
  vim.notify("opened a markdown buffer: " .. ctx.buf)
end)

ft.attach()    -- creates the underlying autocmd; idempotent
ft.stats()     -- { total_keys, total_handlers, keys, attached, mode, autocmds }
ft.handlers()  -- every registration, in dispatch order, with desc and call site
ft.detach()    -- removes it; idempotent, registry survives for a later attach()
```

## Turning it off: `dispatch = false`

```lua
-- per dispatcher, decided by its author
dispatcher.new({ …, dispatch = false })

-- or globally, for a whole session
vim.g.lib_nvim_autocmd_dispatch = false
require("lib.nvim.bindings.autocmd.dispatcher").reattach_all()
```

Bypass mode builds **one plain autocmd per handler** instead of one for all of
them. Everything else is unchanged: the same `key` function runs, the same
globs match, `once` is still per buffer, `unregister(owner)` still works, and
handlers still receive the same `ctx`.

Two reasons it exists:

- **An escape hatch.** A dispatcher makes N features share one object. Before
  this, undoing that meant editing all N call sites. Now it is a flag.
- **Checking the claim.** The cost table at the top of this file is one
  machine and one synthetic benchmark. An argument you cannot re-measure in
  your own config is one you have to take on faith.

The mode is resolved at `attach()`, not at `new()`, so `detach()` → flip →
`attach()` switches a live dispatcher. `reattach_all()` does that for every
dispatcher that is currently attached — dispatchers you had deliberately
detached stay detached. `stats()` and `registry()` report `mode` and how many
autocmds are actually behind the handlers.

### Where bypass is not a perfect A/B

It reproduces the *shape* this module replaced — N autocmds, each doing its own
key work — but not byte-for-byte. Four differences, all of which matter more
for "am I measuring the same program" than for day-to-day use:

| | dispatch | bypass |
| --- | --- | --- |
| a handler that throws | aborts the rest of that event's handlers | the others still run |
| `opts.context` | built once per event | built once per *matching handler* |
| `priority` | honoured on every dispatch | honoured at `attach()`; anything registered later lands last regardless |
| events | one autocmd on the dispatcher's event list | every handler on the **whole** event list, even if its keys only name one event |

The last one is why a bypass measurement is a slight over-estimate of the
pre-dispatcher world: before, a feature listened only to the events it cared
about. Everything the callers here depend on is asserted in both modes from one
suite in `TESTS/autocmd_dispatcher_spec.lua` — a second code path nobody
exercises rots.

## `owner`, and why a shared dispatcher needs it

```lua
ft.register("lua", { load = fn, owner = "my_feature", desc = "what it does" })
ft.unregister("my_feature")   -- returns how many registrations it dropped
```

A plain autocmd is un-registered by re-creating its augroup with
`clear = true`, and that is exactly what an idempotent `setup()` relies on:
tear down, set up again, still one handler. Hand the same handler to a
*shared* dispatcher a second time and it runs twice per event — and there is
no way back short of `detach()`, which takes every other feature's handlers
down with it.

So anything with a setup/teardown cycle must pass `owner` and call
`unregister(owner)` before re-registering. `unregister` also forgets the
`once`-per-buffer bookkeeping for the handlers it drops, so a re-registered
owner starts clean instead of inheriting "already ran" from the cycle before.

## `desc`, and the documentation this would otherwise cost

A dispatcher collapses N handlers into **one** autocmd. That means
`lib.nvim.bindings.autocmd`'s registry — and therefore the generated
`bindings/autocmd/*.md` — can only ever show a single row for it. Left at
that, a page would claim one listener on `BufEnter` for a plugin where ten
features are listening: the same failure the generator exists to prevent, one
level down.

So `dispatcher.registry()` reports every dispatcher with its handler list, and
`docs` renders a **Dispatched handlers** table underneath the record table —
key, `desc`, priority, `once`, and the file:line of the `register()` call.
Give every handler a `desc`; it is that table's "What" column.

`opts.name` is what the dispatcher is called there (default: `opts.group`).

## The `FileType` wrapper

`dispatcher.filetype.new(opts?)` is sugar for the snippet above: it pre-fills
`event = "FileType"` and `key = function(ev) return ev.match end`, and
defaults `context` to a `lib.nvim.buffer.context` snapshot of the triggering
buffer (override via `opts.context`):

```lua
local ft = require("lib.nvim.bindings.autocmd.dispatcher").filetype.new({ group = "MyDispatcher" })

ft.register("lua", function(ctx)
  -- ctx.context is a Lib.Buffer.Context.Ctx — filetype/buftype/modifiable/...
  if ctx.context:is_normal() then
    require("lsp.languages.scripting.lua")
  end
end)

ft.attach()
```

## Handler shape

- **A plain function** `fun(ctx)` — called directly on match.
- **A table** `{ load = fun(ctx), priority?, once? }` — `load` is required to
  exist textually, but only *called* the first time its key actually
  matches; typical use is `load = function() require("some.module") end`,
  where the module's own top-level code does the real work as a side effect
  of being required.

Both shapes receive one `ctx` table: `{ ev, buf, key, context }` — `ev` is
the raw autocmd args, `key` is the concrete value that matched (e.g. the
resolved filetype, useful when a handler is registered under a glob),
`context` is `opts.context(ev)`'s result or `nil` if no `context` was given.

## Keys

A key is either an **exact string** (fast-path equality) or a **glob**
containing `*` (`"noice*"`), matched against the concrete key `opts.key(ev)`
produces for each event. `register()` accepts one key or a list of keys —
one handler registered under `{ "c", "cpp" }` is one registration (shares
one `once` slot across both filetypes); two separate `register()` calls that
happen to close over the same `load` function are two independent
registrations with independent `once` tracking, even though the closures are
identical — this is the fix for a real bug found in the nvim-config
prototype this module is based on (keying `once` by `tostring(load)` there
silently merges two handlers that share a loader).

## Ordering and `once`

Matched handlers for a given event run in ascending `priority` order (default
`0`), ties broken by registration order — sorted once when a key is first
resolved after a `register()` call, not re-sorted on every dispatch.

`once = true` runs a handler at most once **per buffer**, not once globally
(`nvim_create_autocmd`'s own `once` has no per-buffer equivalent). Tracked by
an explicit per-registration id, cleaned up on `BufWipeout` so the tracking
table doesn't grow unbounded across a long session.

## What this does not do

- **Not a performance optimization** over plain autocmds for the common
  case — see the top of this file.
- **Not auto-attach on require.** Nothing runs until `attach()` is called
  explicitly.
- **No re-wrapping of errors.** Registration goes through
  `lib.nvim.bindings.autocmd.create`, which already `pcall`-guards the callback and
  reports failures via `lib.nvim.notify` — a handler error aborts the rest
  of that dispatch's handler loop for that one event, same as a plain
  autocmd callback throwing would.
