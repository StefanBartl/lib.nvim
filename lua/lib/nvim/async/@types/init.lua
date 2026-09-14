---@meta
---@module 'lib.nvim.async.@types'

---Options for `require("lib.nvim.async").run`.
---@class Lib.Async.RunOpts
---@field tag? string Prefix for the default error notification (default `"lib.nvim.async"`); ignored when `on_error` is set.
---@field on_error? fun(err: any) Called instead of the default `vim.notify` when the coroutine body raises. Not `vim.schedule`-wrapped — it may run in a fast-event context.

---@class Lib.Async
---@field await fun(starter: fun(resume: fun(...))): ... Suspend until `starter` calls its `resume`.
---@field run fun(body: function, on_done?: function, opts?: Lib.Async.RunOpts) Drive an `await`-using coroutine to completion.
---@field wrap fun(fn: function, argc: integer): fun(...): ... Turn a callback-style function (callback last, at position `argc`) into an awaitable one.
---@field Semaphore Lib.Async.SemaphoreClass
---@field Condvar Lib.Async.CondvarClass
---@field LatestWins Lib.Async.LatestWinsClass
---@field latest_wins fun(): Lib.Async.LatestWins Shorthand for `LatestWins.new()`.

---@class Lib.Async.SemaphoreClass
---@field new fun(permits: integer): Lib.Async.Semaphore

---Counting semaphore instance; `:acquire()` is only valid inside an `async.run` body.
---@class Lib.Async.Semaphore
---@field permits integer Currently free permits.
---@field waiters fun(...)[] Suspended acquirers, longest-waiting first.
---@field acquire fun(self: Lib.Async.Semaphore) Take a permit, suspending until one is free.
---@field release fun(self: Lib.Async.Semaphore) Give a permit back, handing it straight to a waiter if there is one.

---@class Lib.Async.CondvarClass
---@field new fun(): Lib.Async.Condvar

---Condition variable instance; `:wait()` is only valid inside an `async.run` body.
---@class Lib.Async.Condvar
---@field waiters fun(...)[] Suspended waiters, longest-waiting first.
---@field wait fun(self: Lib.Async.Condvar) Suspend until notified.
---@field notify_one fun(self: Lib.Async.Condvar) Wake the longest-waiting coroutine, if any.
---@field notify_all fun(self: Lib.Async.Condvar) Wake every waiting coroutine.

---@class Lib.Async.LatestWinsClass
---@field new fun(): Lib.Async.LatestWins

---"Newest request wins" token gate instance. Not tied to `M.run`; usable
---around any callback-based async call.
---@class Lib.Async.LatestWins
---@field token integer The most recently minted token.
---@field begin fun(self: Lib.Async.LatestWins): integer Mint a new token, superseding the previous one.
---@field is_current fun(self: Lib.Async.LatestWins, token: integer): boolean Whether `token` is still the newest one minted.
---@field if_current fun(self: Lib.Async.LatestWins, token: integer, fn: fun(...), ...) Run `fn` only if `token` is still current.

return {}
