# `lib.nvim.async`

Minimal coroutine async/await over libuv, plus the two control primitives
that need it (`Semaphore`, `Condvar`).

The whole module rests on one protocol: `await(starter)` yields the
`starter` function, and the driver in `run()` calls `starter(resume)`.
Whatever `resume` receives becomes `await`'s return values. A libuv
callback is passed straight through as `resume`; a semaphore waiter is
just a stored `resume` called later. No promise/future objects, no
scheduler beyond `step()`.

This is the extraction of a private helper that
[`fs.collect_recursive`](../fs/collect_recursive/README.md) and
[`fs.write.async`](../fs/write/async/README.md) each carried their own
(already diverging) copy of — written against real duplication rather than
speculatively. Both now delegate here.

## Why `lib.nvim`, not `lib.lua`

`run`'s completion and error paths must hop through `vim.schedule`: every
resume past the first happens inside a raw libuv callback (fast-event
context), where `vim.fn`/`vim.api` are off limits. `Semaphore`/`Condvar`
are pure coroutine mechanics, but only mean anything under this runner, so
they live here too rather than in the editor-independent tree.

## Usage

```lua
local async = require("lib.nvim.async")
local uv = vim.uv or vim.loop

-- (path, flags, mode, cb) -> callback is argument 4
local fs_open = async.wrap(uv.fs_open, 4)
local fs_close = async.wrap(uv.fs_close, 2)

async.run(function()
  local err, fd = fs_open("/tmp/x", "r", 438)
  if err then
    return nil, err
  end
  fs_close(fd)
  return fd
end, function(fd, err)
  -- vim.schedule-dispatched: safe to touch vim.api here
  if not fd then
    vim.notify("open failed: " .. tostring(err))
  end
end, { tag = "my.module" })
```

### Semaphore

Bound how many coroutines do something at once — e.g. capping concurrent
spawns so a directory walk doesn't open a thousand file descriptors:

```lua
local sem = async.Semaphore.new(4)

async.run(function()
  sem:acquire()
  local result = do_something_awaitable()
  sem:release()
  return result
end)
```

### Condvar

Suspend until another coroutine signals:

```lua
local cv = async.Condvar.new()

async.run(function()
  cv:wait()          -- suspends here
  return "woken"
end, function(msg) vim.notify(msg) end)

-- later, from anywhere:
cv:notify_one()      -- or cv:notify_all()
```

## API

| Function                        | Meaning                                                                 |
|-----------------------------------|----------------------------------------------------------------------------|
| `async.await(starter)`             | Suspend until `starter(resume)` fires `resume`; returns what it was given |
| `async.run(body, on_done?, opts?)` | Drive an `await`-using coroutine; `on_done` gets `body`'s return values, `vim.schedule`-dispatched |
| `async.wrap(fn, argc)`             | Callback-style `fn` (callback last, at position `argc`) → awaitable        |
| `async.Semaphore.new(permits)`     | `:acquire()` (awaitable), `:release()`                                     |
| `async.Condvar.new()`              | `:wait()` (awaitable), `:notify_one()`, `:notify_all()`                    |

`opts` for `run`:

| Field       | Default              | Meaning                                                          |
|--------------|-----------------------|----------------------------------------------------------------------|
| `tag`        | `"lib.nvim.async"`    | Prefix for the default error notification                            |
| `on_error`   | `vim.notify`-based    | Called instead when `body` raises. **Not** `vim.schedule`-wrapped — it may run in a fast-event context |

## Semantics worth knowing

- **Errors don't propagate to the caller.** By the time `body` raises, the
  original call stack is gone (the coroutine is being resumed from a libuv
  callback). The error goes to `opts.on_error`, defaulting to a
  `vim.notify` so it reaches `:messages` instead of vanishing into the
  event loop.
- **`release`/`notify_*` resume synchronously.** They do not return until
  the resumed coroutine yields again or finishes. This keeps handover
  ordering obvious (no scheduler round-trip between a release and the
  acquire it unblocks), at the cost of nesting the resumed coroutine's
  stack under the releasing one.
- **`Semaphore:release` hands the permit straight to a waiter** when there
  is one, rather than incrementing the count — otherwise a queued waiter
  could be starved by a later `acquire()` racing in.
- **`Condvar:notify_all` swaps the waiter list out first**, so a coroutine
  that re-`wait()`s while being woken queues for the *next* notify instead
  of being woken again by this one.
- **No parallelism.** This is concurrency over one event loop: `await`
  hands control back so other work proceeds, but nothing runs
  simultaneously.
