---@module 'lib.nvim.async'
--- Minimal coroutine async/await over libuv, plus the two control
--- primitives that need it (`Semaphore`, `Condvar`).
---
--- The whole thing rests on one protocol: `await(starter)` yields the
--- `starter` function, and the driver in `run()` calls `starter(resume)`.
--- Whatever `resume` receives becomes `await`'s return values. A libuv
--- callback is passed straight through as `resume`; a semaphore waiter is
--- just a stored `resume` called later. No promise/future objects, no
--- scheduler beyond `step()`.
---
--- Written against real duplication rather than speculatively: this is
--- the extraction of the private `await`/`run_async` helper that
--- `fs.collect_recursive` and `fs.write.async` each carried their own
--- (already diverging) copy of.
---
--- Neovim-side by design, not `lib.lua`: `run`'s completion and error
--- paths must hop through `vim.schedule`, because every resume after the
--- first happens inside a raw libuv callback (fast-event context) where
--- `vim.fn`/`vim.api` are off limits. `Semaphore`/`Condvar` are pure
--- coroutine mechanics, but only mean anything under this runner, so they
--- live here too.
---
---```lua
--- local async = require("lib.nvim.async")
---
--- local uv = vim.uv or vim.loop
--- local fs_open = async.wrap(uv.fs_open, 4) -- (path, flags, mode, cb)
---
--- async.run(function()
---   local err, fd = fs_open("/tmp/x", "r", 438)
---   if err then
---     return nil, err
---   end
---   return fd
--- end, function(fd, err)
---   -- vim.schedule-dispatched: safe to touch vim.api here
--- end, { tag = "my.module" })
---```

require("lib.nvim.async.@types")

local class = require("lib.lua.class")

-- LuaJIT (Neovim's Lua runtime) has neither `table.pack` nor Lua 5.2+'s
-- `table.unpack` — only the global `unpack`, and no `pack` at all.
---@diagnostic disable-next-line: deprecated
local unpack = table.unpack or unpack
local pack = table.pack or function(...)
  return { n = select("#", ...), ... }
end

local M = {}

-- =========================================================
-- Core
-- =========================================================

--- Suspend the running coroutine until `starter` settles. `starter(resume)`
--- must arrange for `resume(...)` to be called — typically by passing it
--- straight through as a libuv callback. Whatever `resume` receives becomes
--- this call's return values. Only valid inside a coroutine driven by
--- `M.run`.
---@param starter fun(resume: fun(...))
---@return ... # whatever `resume` was called with
function M.await(starter)
  return coroutine.yield(starter)
end

--- Drive a coroutine written against `M.await` to completion.
---
--- `on_done` receives `body`'s return values (all of them, embedded `nil`s
--- included) and is `vim.schedule`-dispatched — every resume past the
--- first happens inside a raw libuv callback, so nothing after the last
--- `await()` may safely touch `vim.fn`/`vim.api` without that hop.
---
--- An error thrown inside `body` does not propagate to the original
--- caller (its stack is long gone by then); it goes to `opts.on_error`,
--- which defaults to a `vim.notify` prefixed with `opts.tag` so it lands
--- in `:messages` instead of vanishing into the event loop.
---@param body fun(): ...
---@param on_done? fun(...)
---@param opts? Lib.Async.RunOpts
function M.run(body, on_done, opts)
  opts = opts or {}
  local co = coroutine.create(body)

  local function step(...)
    local results = pack(coroutine.resume(co, ...))
    if not results[1] then
      local err = results[2]
      if opts.on_error then
        opts.on_error(err)
      else
        local tag = opts.tag or "lib.nvim.async"
        vim.schedule(function()
          vim.notify("[" .. tag .. "] " .. tostring(err), vim.log.levels.ERROR)
        end)
      end
      return
    end
    if coroutine.status(co) == "dead" then
      if on_done then
        vim.schedule(function()
          on_done(unpack(results, 2, results.n))
        end)
      end
      return
    end
    -- results[2] is the starter function `body` handed to `await()`,
    -- expecting `step` itself as its `resume` callback.
    results[2](step)
  end

  step()
end

--- Turn a callback-style function into an awaitable one. `argc` is the
--- total argument count of `fn` *including* its callback, which must be
--- the last parameter — `uv.fs_open(path, flags, mode, cb)` is `argc = 4`.
---
--- The returned function is only callable inside an `M.run` body; it
--- returns whatever `fn` passes to its callback.
---@param fn function
---@param argc integer
---@return fun(...): ...
function M.wrap(fn, argc)
  return function(...)
    local args = pack(...)
    return M.await(function(resume)
      args[argc] = resume
      -- Callers may legitimately pass fewer than argc-1 arguments (a uv
      -- function with optional parameters); the callback still has to land
      -- in slot argc, so the arg count grows to match rather than
      -- truncating it back to what was actually passed.
      args.n = math.max(args.n, argc)
      fn(unpack(args, 1, args.n))
    end)
  end
end

-- =========================================================
-- Control primitives
-- =========================================================

--- Counting semaphore: at most `permits` coroutines hold it at once.
--- `:acquire()` is awaitable and suspends when none are free.
---
--- Note that `:release()` resumes a waiting coroutine *synchronously*,
--- so it does not return until that coroutine yields again or finishes.
--- That keeps the handover ordering obvious (no scheduler round-trip
--- between a release and the acquire it unblocks) at the cost of nesting
--- the resumed coroutine's stack under the releasing one.
local Semaphore = class.new("Semaphore")

---@param permits integer
function Semaphore:init(permits)
  self.permits = permits
  self.waiters = {}
end

--- Take a permit, suspending until one is free. Awaitable.
function Semaphore:acquire()
  if self.permits > 0 then
    self.permits = self.permits - 1
    return
  end
  M.await(function(resume)
    self.waiters[#self.waiters + 1] = resume
  end)
end

--- Give a permit back. Hands it straight to the longest-waiting acquirer
--- if there is one — the permit count only grows when nobody is waiting,
--- otherwise a waiter could be starved by a later `acquire()` racing in.
function Semaphore:release()
  local waiter = table.remove(self.waiters, 1)
  if waiter then
    waiter()
  else
    self.permits = self.permits + 1
  end
end

M.Semaphore = Semaphore

--- Condition variable: `:wait()` suspends until someone notifies.
--- Like `Semaphore:release`, notifying resumes waiters synchronously.
local Condvar = class.new("Condvar")

function Condvar:init()
  self.waiters = {}
end

--- Suspend until a `notify_one`/`notify_all` reaches this waiter. Awaitable.
function Condvar:wait()
  M.await(function(resume)
    self.waiters[#self.waiters + 1] = resume
  end)
end

--- Wake the longest-waiting coroutine, if any.
function Condvar:notify_one()
  local waiter = table.remove(self.waiters, 1)
  if waiter then
    waiter()
  end
end

--- Wake every waiting coroutine. The waiter list is swapped out first, so
--- a coroutine that re-`wait()`s while being woken queues up for the next
--- notify instead of being woken again by this one.
function Condvar:notify_all()
  local waiters = self.waiters
  self.waiters = {}
  for _, waiter in ipairs(waiters) do
    waiter()
  end
end

M.Condvar = Condvar

---@type Lib.Async
return M
