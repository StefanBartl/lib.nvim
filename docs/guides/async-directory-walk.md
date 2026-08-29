# Async directory walk

**Modules:** [`lib.nvim.fs.collect_recursive`](../../lua/lib/nvim/fs/collect_recursive/README.md)
(`collect_async`/`files_async`/`dirs_async`),
[`lib.nvim.fs.scan_cached`](../../lua/lib/nvim/fs/scan_cached/README.md)
(`scan_async`),
[`lib.nvim.fs.scan_roots`](../../lua/lib/nvim/fs/scan_roots/README.md)
(`scan_async`)
· **API:** [filesystem.md](../API/filesystem.md#directory-scanning--walking)
· **Spec:** [`TESTS/async_walk_spec.lua`](../../TESTS/async_walk_spec.lua)

## The problem

`collect_recursive.collect()` — the walker underneath both `scan_cached`
and `scan_roots` — is synchronous: `uv.fs_scandir`/`uv.fs_stat` called
*without* a callback block the caller until the syscall returns. That's
fine for a handful of directories, but stalls Neovim's entire main loop
(input, redraws, everything) for the duration of a large tree — a
`node_modules`, a monorepo. This was the single concrete, confirmed gap
that came out of the plenary/libuv research,
flagged there as the largest real, measurable win available: everything
else in that research was either already covered or not worth building
without a concrete consumer.

libuv's own `fs_scandir`/`fs_stat` *do* support a callback form that's
genuinely async — the event loop keeps servicing input and redraws while a
scan is in flight. But threading raw callbacks through recursive directory
descent produces exactly the callback-pyramid mess the same research
flagged in `fs/write/async` (nested `fs_open` → `fs_write` → `fs_close`).

## The solution

A minimal coroutine-based async/await: `await(starter)` suspends the
running coroutine until `starter`'s callback fires; `run(body, on_done)`
drives a coroutine written against `await()` to completion. `walk_async` —
the async counterpart to the existing synchronous `walk` — reads like a
plain recursive function (one `await()` per libuv call) while every
`await()` actually yields control back to the event loop.

That helper started out private to `collect_recursive`, was copied into
`fs/write/async`, and now lives in [`lib.nvim.async`](../../lua/lib/nvim/async/README.md)
— extracted once the duplication was real rather than hypothetical (see
"What this deliberately is not" below for what changed since).

```lua
local collect_recursive = require("lib.nvim.fs.collect_recursive")

local cancel = collect_recursive.collect_async("/repo", { kind = "files" }, function(paths)
  -- called once, vim.schedule-dispatched, never for a cancelled walk
end)
-- cancel()  -- stop early if the caller no longer needs the result
```

`scan_cached.scan_async` and `scan_roots.scan_async` build directly on this:
a cache hit still calls `on_done` (so both branches behave uniformly to a
caller), a miss walks via `collect_async` instead of the blocking walk.
`scan_roots.scan_async` chains one root's `collect_async` into the next
through its own `on_done`, same as the synchronous version's `for` loop.

## What this deliberately is not

**Not a wall-clock speedup.** This walks one directory at a time — async
(never blocks the main loop), but not parallel. The fix targets UI
responsiveness during a large scan, not raw scan throughput; per-call
event-loop round trips can make it *slower* in wall time than the
synchronous walk for a tree that would have finished fast anyway. Sibling
directories are visited sequentially on purpose, to keep the coroutine
driver simple — matching `scan_roots`'s existing "sequential by design"
stance on multiple roots.

**Superseded:** this section used to argue that `await`/`run_async` were
deliberately scoped to this one recursive-walk problem and should not
become a general primitive. A second consumer (`fs/write/async`) then
copied them, and the pair was extracted into
[`lib.nvim.async`](../../lua/lib/nvim/async/README.md), which now also
carries the `wrap`/`Semaphore`/`Condvar` the research had left out. The
restraint was about not building it *speculatively* — it was built once
two real consumers existed.

## Cancellation

`collect_async` returns a `cancel()` function. Calling it stops the walk
after its current in-flight libuv call settles, and `on_done` is not called
at all afterward — not "called with a partial result," genuinely skipped.
Useful when a consumer (a picker, a live filter) is closed or superseded
mid-scan.

## Verified equivalence

The spec walks the same fixture tree through both `collect`/`collect_async`
(and `files`/`files_async`, `dirs`/`dirs_async`) and asserts identical
result sets — same files, same directories, same `ignore`-predicate
pruning, same empty-list behavior for a nonexistent root — plus the
`scan_cached`/`scan_roots` TTL/cache-hit/refresh semantics carried over
unchanged onto their `_async` counterparts.

## Related

- [subprocess-env.md](subprocess-env.md) — the other item from the same
  roadmap priority list, `cross.run`'s default environment enrichment
