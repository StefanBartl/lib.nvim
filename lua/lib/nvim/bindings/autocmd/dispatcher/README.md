# `lib.nvim.bindings.autocmd.dispatcher`

One autocmd, many handlers — a generic, event-agnostic dispatcher factory,
plus a `FileType` convenience wrapper on top.

This README covers the full reasoning, including why this is **not** a
performance win over plain autocmds for the common case — it genuinely does
more work per event than native dispatch, and the honest reasons to reach
for it anyway (uniform lazy-loading, deterministic `priority` ordering,
per-buffer `once`).

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
ft.stats()     -- { total_keys, total_handlers, keys, attached }
ft.detach()    -- removes it; idempotent, registry survives for a later attach()
```

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
