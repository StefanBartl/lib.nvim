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

`acquire`/`release` by hand leak the permit when the body throws. The
leak-proof form is `sem:with(body, ...)`: it holds a permit around
`body(...)`, releases it on every path and returns `ok, ...` like
`lib.lua.error.safe_call` (a structured error with a traceback on failure).
`body` may itself `await`.

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

### map_limit — a bounded fan-out over callback-style workers

"Do this for each of N repositories/files/servers, at most `limit` at a time":

```lua
local git = require("lib.nvim.git")

local handle = async.map_limit(repos, 4, function(repo, index, done)
  -- start the work; call done(result, err) exactly once when it finishes.
  -- Returning a handle with stop() lets handle.stop() kill what is in flight.
  return git.log_async("HEAD", { dir = repo, max_count = 5 }, done)
end, function(results, errors, stopped)
  -- vim.schedule-dispatched. results[i] / errors[i] belong to repos[i].
end, {
  on_progress = function(count, total, index, result, err) end,
})

-- handle.stop(): stop in-flight workers that returned a handle, start no more,
-- call on_done(..., true) once; anything finishing later is discarded.
```

Unlike `Semaphore`, the worker is a plain callback function — no coroutine, so
it fits `run_async_captured` and every `*_async` helper as they are. The
semantics worth knowing:

- **A worker that finishes synchronously is fine.** The loop is guarded
  against re-entrancy, so 20 000 workers calling `done` immediately neither
  recurse nor overflow the stack.
- **A worker that throws is that item's error**, in `errors[i]` — it neither
  stalls the run nor escapes into the caller. A worker that never calls `done`
  stalls the run, as with any hand-built pool.
- **`done` is idempotent**: a second call (or a call after `stop()`) is
  ignored.
- **`on_progress` and `on_done` never run in a fast-event context.** They are
  `vim.schedule`d (progress after every finished item, in completion order), in
  the order the events happened. `worker` is called synchronously — from inside
  `map_limit` for the first `limit` items, and for the rest in whatever context
  `done` was called from. That is the main loop for `run_async_captured` and every
  `*_async` helper; a worker driven by a raw libuv callback must not touch
  `vim.api` itself.
- **`stop()` ends the run first, then stops the workers**, so a worker handle
  whose `stop()` reports back through `done` cannot start the next item, and a
  handle a worker returns after it stopped the run is stopped too. The error a
  worker throws reaches `errors[i]` unchanged (a table stays a table).
- `limit` is clamped to at least 1; an empty list still reports (asynchronously).

## API

| Function                        | Meaning                                                                 |
|-----------------------------------|----------------------------------------------------------------------------|
| `async.await(starter)`             | Suspend until `starter(resume)` fires `resume`; returns what it was given |
| `async.run(body, on_done?, opts?)` | Drive an `await`-using coroutine; `on_done` gets `body`'s return values, `vim.schedule`-dispatched |
| `async.wrap(fn, argc)`             | Callback-style `fn` (callback last, at position `argc`) → awaitable        |
| `async.map_limit(items, limit, worker, on_done, opts?)` | Run a callback-style `worker(item, index, done)` over every item, at most `limit` in flight; `on_done(results, errors, stopped)`; returns `{ stop }` |
| `async.Semaphore.new(permits)`     | `:acquire()` (awaitable), `:release()`, `:with(body, ...)` (acquire, run guarded, always release) |
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
