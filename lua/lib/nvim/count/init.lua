---@module 'lib.nvim.count'
-- =========================================================
-- Count-prefix helpers for keymaps.
--
-- Reading `vim.v.count` correctly is a three-way decision that gets made
-- wrong often enough to be worth a module: `count1` when "no count" means
-- "once", raw `count` when 0 has its own meaning (a plugin default), and a
-- clamp whenever the value indexes into something bounded.
--
-- `times` and `chain` cover the two ways an action repeats: synchronously,
-- or one-at-a-time gated on an external completion signal.
-- =========================================================

local notify = require("lib.nvim.notify").create("[lib.nvim.count]")

local M = {}

--- Upper bound applied when the caller gives no `max`.
---
--- A count is typed, so it can be fat-fingered: `100<leader>x` is a plausible
--- slip and `10000<leader>x` is almost never intentional. Both `times` and
--- `chain` cap by default rather than trusting the keypress.
M.DEFAULT_MAX = 1000

--- The count for "no count means once" actions -- `vim.v.count1`.
---
--- This is the right default for anything that repeats: motions, cycles,
--- next/prev. Never returns 0.
---@return integer
function M.get()
  return vim.v.count1
end

--- The raw count -- `vim.v.count`, 0 when the user typed none.
---
--- Use this only when 0 carries its own meaning, e.g. "no count -> half a
--- window height". Otherwise `get()` is what you want.
---@return integer
function M.raw()
  return vim.v.count
end

--- Did the user actually type a count?
---@return boolean
function M.given()
  return vim.v.count ~= 0
end

--- `vim.v.count1`, clamped into `[min, max]`.
---
--- For counts that index into something bounded (heading depth, list slot,
--- zoom level) an out-of-range count must not reach the caller as-is.
---@param min integer
---@param max integer
---@return integer
function M.clamp(min, max)
  local n = vim.v.count1
  if n < min then
    return min
  end
  if n > max then
    return max
  end
  return n
end

--- Run `fn` once per count, synchronously.
---
--- Only safe when `fn` completes before it may be called again. If the action
--- is asynchronous or protocol-gated (a debug-adapter step, a request/response
--- round trip), use `chain` instead -- firing the second call while the first
--- is still in flight is what `chain` exists to prevent.
---
--- `fn` receives the 1-based iteration index. Returning `false` from it stops
--- the loop early (a boundary was hit; carrying on would be a no-op at best).
---@param fn fun(i: integer): boolean|nil
---@param opts { count?: integer, max?: integer }|nil
---@return integer ran  # how many times `fn` actually ran
function M.times(fn, opts)
  opts = opts or {}
  local n = math.min(opts.count or vim.v.count1, opts.max or M.DEFAULT_MAX)

  for i = 1, n do
    if fn(i) == false then
      return i
    end
  end
  return n
end

--- Repeat an action `count` times, each next call gated on an external
--- "the previous one finished" signal.
---
--- Generalized from dap.nvim's `counted_step()`, where a naive
--- `for i = 1, count do step() end` violates the DAP spec: a step request
--- while the thread is still running from the previous one is invalid. The
--- same shape fits any action whose completion arrives as an event rather
--- than as a return: a request/response round trip, a job, a queued fetch.
---
--- `subscribe` registers the caller's own listeners and returns a function
--- that removes them again. It is handed:
---   * `advance` -- call when one unit of work has completed
---   * `abort`   -- call when the thing being driven went away (session
---                  terminated, job died); the chain is dropped, and no
---                  dangling listener waits for a signal that never comes
---
--- With no count -- the overwhelmingly common case -- `action` is called
--- directly and `subscribe` is never invoked, so there is zero overhead and
--- nothing to clean up.
---@param opts Lib.Count.ChainOpts
---@return boolean chained  # false when it ran as a plain single call
function M.chain(opts)
  if type(opts) ~= "table" or type(opts.action) ~= "function" then
    notify.error("chain: opts.action must be a function")
    return false
  end

  local count = opts.count or vim.v.count1
  if count <= 1 then
    opts.action()
    return false
  end

  if type(opts.subscribe) ~= "function" then
    -- Without a completion signal there is no safe way to pace the repeats.
    -- Firing them back-to-back is exactly the bug this function prevents, so
    -- degrade to a single call rather than to the unsafe loop.
    notify.error("chain: opts.subscribe must be a function; running once instead")
    opts.action()
    return false
  end

  -- Units still owed *beyond* the one fired at the end of this function.
  local remaining = math.min(count, opts.max or M.DEFAULT_MAX) - 1

  ---@type fun()|nil
  local unsubscribe
  local dead = false

  local function stop()
    dead = true
    if unsubscribe then
      local fn = unsubscribe
      unsubscribe = nil
      fn()
    end
  end

  local function advance()
    -- Unsubscribing is the caller's job and may land a beat late: a signal
    -- already queued when `abort` ran still arrives afterwards. The chain
    -- therefore refuses to be resurrected on its own account, rather than
    -- trusting every driver to detach synchronously.
    if dead then
      return
    end
    if remaining <= 0 then
      -- The call that satisfies `count` already fired; this signal just
      -- confirms it landed. Nothing left to do.
      stop()
      return
    end
    remaining = remaining - 1
    opts.action()
  end

  local ok, ret = pcall(opts.subscribe, advance, stop)
  if not ok then
    notify.error(("chain: subscribe failed:\n%s"):format(ret))
    opts.action()
    return false
  end
  if type(ret) == "function" then
    unsubscribe = ret
  end

  opts.action()
  return true
end

---@type Lib.Count
return M
