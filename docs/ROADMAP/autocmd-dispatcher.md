# `lib.nvim.autocmd.dispatcher` — one autocmd, many handlers

> **Status:** concept, not implemented. Written in response to: "ich habe in
> meiner nvim config einen autocmd dispatcher, das ist vorteilhaft weil man
> alle autocmds bündeln kann, das ist performanter und übersichtlicher —
> kann man das per lib anbieten, wenn es Sinn macht?"
>
> **Short answer: yes, and it does make sense — but the version worth
> shipping is smaller and more general than the one in the config.** The
> reasoning below is based on reading the actual implementation
> (`lua/autocmds/events/utils/filetype.lua` in the nvim config) and on
> checking how the personal plugins register autocmds today.

## What the config's dispatcher does

One `FileType` autocmd with `pattern = "*"`, which then:

1. looks up handlers by filetype, with `*` wildcard patterns (`"noice*"`)
2. sorts matched handlers by `priority` (lower = earlier)
3. supports `once = true` per handler **per buffer**, tracked in a
   weak-keyed table
4. lazy-loads each handler's module only when it actually matches
   (`load = function() return require("…") end`)
5. `pcall`-guards both the load and the call, reporting via notify
6. dispatches with a cached buffer context (`lib.nvim.buffer.context`)
7. exposes `register()` for external additions, plus `get_stats()` /
   `print_registry()` for introspection

That is a well-built piece of code. Points 3–5 in particular are the parts
people usually get wrong or skip.

## Is the premise right? Partly — and the honest part matters

The stated motivation is "performanter und übersichtlicher". Those two are
not equally true, and shipping this into a shared library on a
half-incorrect premise would spread a misconception:

**Übersichtlicher: yes, clearly.** One registry, one place to see every
filetype hook, priorities visible, lazy-loading uniform instead of
per-module ad hoc. This is the real, durable win.

**Performanter: much less than it looks, and occasionally the opposite.**
Neovim's autocmd dispatch is C-side and already filters by event and
pattern. Ten `FileType` autocmds with `pattern = "lua"` cost ten cheap
pattern comparisons for a non-`lua` buffer, and Neovim never enters Lua for
them at all. The dispatcher replaces that with **one** autocmd that fires
for *every* filetype and then does the matching in Lua — including a
`pairs()` scan over all registered patterns, a `table.sort` per dispatch,
and a `matches_pattern` call per registered pattern.

So for a buffer with no handlers, the dispatcher does *more* work than
native autocmds would, not less. What it genuinely buys:

- **Lazy loading.** This is the actual performance win, and it is real: the
  handler modules aren't `require`d at startup. But that is a property of
  the `load = function() … end` indirection, **not** of the bundling.
- **Deterministic ordering.** Native autocmds fire in registration order,
  which across plugins is effectively arbitrary. `priority` makes it
  explicit — a correctness feature more than a speed one.
- **Per-buffer `once`.** `nvim_create_autocmd`'s own `once` is
  once-globally, not once-per-buffer. There is no native equivalent.

**None of that is a reason not to ship it** — ordering, per-buffer `once`
and uniform lazy loading are worth having on their own. It is a reason to
describe it accurately in the docs, so nobody adopts it expecting a speedup
that isn't there and then measures a regression.

## Does it generalize? Yes — verified, not assumed

Checked across the personal plugins: **17 `FileType` autocmd registrations**
spread over `filetree.nvim`, `markdown.nvim`, `language.nvim`,
`insights.nvim`, `cascade.nvim` and others, each hand-rolling its own
`nvim_create_autocmd` + guard + (sometimes) once-tracking. That is exactly
the duplication `lib.nvim` exists to absorb, and the same argument that
justified `lib.nvim.buffer.context` (which this very dispatcher already
consumes, per its own comment: "formerly the local prototype at
autocmds/benchmarks/context/buffer.lua, now shared via lib.nvim").

## What should actually be in lib.nvim

The config's version is `FileType`-specific: it reads `ev.match` as a
filetype, its registry is keyed by filetype, and `get_handlers` implements
filetype-glob matching. Lifting it verbatim would put a single-event helper
into a general-purpose library.

**Proposal: a generic, event-agnostic dispatcher factory, with a `FileType`
convenience wrapper on top.**

```lua
local dispatcher = require("lib.nvim.autocmd.dispatcher")

-- Generic: works for any event whose `match`/`buf` you want to key on.
local ft = dispatcher.new({
  event = "FileType",
  group = "MyFiletypeDispatcher",
  key = function(ev) return ev.match end,      -- what to look handlers up by
  context = function(ev)                        -- optional shared context
    return require("lib.nvim.buffer.context").get(ev.buf)
  end,
})

ft.register("lua", {
  load = function() return require("lsp.languages.scripting.lua") end,
  priority = 10,
  once = true,          -- per buffer
})

ft.register({ "c", "cpp" }, { load = …, priority = 10, once = true })
ft.register("noice*", { load = … })            -- glob patterns

ft.attach()             -- creates the single autocmd
ft.detach()             -- removes it; idempotent
ft.stats()              -- { total_keys, total_handlers, keys, handlers }
```

Design points, each with a reason:

- **`key` is a function, not hardcoded.** `FileType` keys on `ev.match`;
  a `BufWritePre` dispatcher would key on the extension or the filetype of
  `ev.buf`; a `User` dispatcher keys on the user-event name. One
  abstraction, not one per event.
- **`once` stays per-buffer** and keeps the weak-keyed tracker — that is the
  feature with no native equivalent, and the weak table is what stops it
  leaking across buffer lifetimes. Worth preserving exactly as written.
- **`attach()`/`detach()` instead of `setup()`.** Matches
  `lib.nvim.docmap`'s `install()`/`uninstall()` and `proc_trace`'s
  `start()`/`stop()` — this repo already has a teardown convention, and a
  dispatcher that can't be torn down is untestable.
- **Handlers can be plain functions**, not only `{ load = … }` tables. The
  lazy-load indirection is the point when the handler is a module, but
  requiring a closure that returns a closure for a two-line inline handler
  is friction.
- **Reuse `lib.nvim.autocmd.create`** for the actual registration, so the
  existing `pcall`-guard + notify error path is not reimplemented. The
  config's dispatcher wraps handlers in its *own* `pcall`s on top of
  `Autocmd.create`'s — one of those layers is redundant and the shared
  version should have exactly one.

## Two improvements over the config version

Found while reading it, both worth fixing in the shared version rather than
copying forward:

1. **`get_handlers` sorts on every dispatch.** The handler set for a given
   key only changes on `register()`. Sorting per event is wasted work on a
   path that fires for every buffer. **Sort at registration**, cache the
   resolved list per key, invalidate on `register()`. This is a real
   (if small) win, and it partially offsets the "dispatcher does more work
   than native" point above.

2. **`once` is keyed by `tostring(handler.load)`.** That is the address of
   the closure — stable within a session, but it silently collides if two
   handlers share the same `load` function (e.g. `c` and `cpp` both loading
   `lsp.languages.systems.c` — which the config does *today*). Two
   filetypes sharing a loader means the second one's `once` is considered
   already-satisfied for that buffer. Use an explicit per-registration id
   (an incrementing counter captured at `register()` time) instead.

Point 2 is a latent bug in the current config, not a hypothetical: `c` and
`cpp` both use `load = function() return require("lsp.languages.systems.c") end`.
Two *distinct* closures there, so `tostring` differs and it happens to work
— but the moment someone factors that shared loader into one variable, the
bug appears with no visible cause. Worth fixing by construction.

## What it should *not* do

- **Not replace `lib.nvim.autocmd.create`.** Most autocmds are one-offs and
  the dispatcher is overhead for them. The dispatcher earns its keep at
  ~5+ handlers on one event; below that, a plain autocmd is simpler and
  faster.
- **Not auto-attach on require.** Same rule as `docmap.command.setup()` —
  requiring a lib module must never register anything in the user's editor
  by itself.
- **Not claim to be faster than native autocmds.** See above; the README
  should state plainly what it does and doesn't buy.

## Recommendation

**Ship it**, as `lib.nvim.autocmd.dispatcher`, generic over the event, with
the two fixes above and honest performance framing. The config keeps its
`FileType` registry as a thin call into it, losing ~200 lines of
infrastructure and keeping only the handler table — which is the part that's
actually config-specific.

Phasing:

1. Generic factory + `register`/`attach`/`detach`/`stats`, `once`-per-buffer
   with counter-based ids, sort-at-registration.
2. Migrate the nvim config's `autocmds.events.utils.filetype` onto it,
   keeping the same handler table (proves the abstraction against its
   original use case).
3. Optionally migrate the per-plugin `FileType` registrations that would
   benefit; most probably won't (they're single-handler), and that's a fine
   outcome — the win was never "everything must use it".

## Open questions

1. **One dispatcher per event, or one shared across events?** Per-event is
   simpler and matches how the config uses it. A shared one keyed by
   `(event, key)` would allow a single registry for the whole config, at the
   cost of a more complex lookup. Leaning per-event.
2. **Should `stats()`/`print_registry()` move into `docmap`'s orbit?** They
   are introspection over a registry, which is close to what docmap does for
   modules. Probably keep them local — different data, different lifecycle.
3. **Buffer-context coupling.** The config's version always builds a
   `buffer.context`. Making that an optional `context` callback (as above)
   keeps the dispatcher usable for events that have no buffer, but means the
   `FileType` wrapper has to supply it. Worth confirming that's not
   friction in practice.
