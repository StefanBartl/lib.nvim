---@module 'lib.nvim.patterns.retry_backoff'
--- Retry with exponential backoff, callback style (non-blocking).
---
--- `run(task, opts)` calls `task(attempt, done)`; the task reports with `done(ok, value_or_err)`. On
--- failure it waits `delay(attempt)` ms and tries again until `max_attempts` is used up or
--- `should_retry(err, attempt)` says no. `opts.on_done(ok, value_or_err, attempts)` gets the end result.
---
--- ```lua
--- local retry = require("lib.nvim.patterns.retry_backoff")
--- retry.run(function(attempt, done)
---   fetch(url, function(err, body) done(err == nil, err or body) end)
--- end, { max_attempts = 4, base_ms = 200, on_done = function(ok, res) ... end })
--- ```
---
--- Delay: `base_ms * factor^(attempt-1)`, capped at `max_ms`; with `jitter` a random 50-100 % of it.
--- `opts.sleep(ms, cb)` is injectable (tests), the default is `vim.defer_fn`.

require("lib.nvim.patterns.retry_backoff.@types")

local M = {}

---Delay in ms before the retry that follows failed attempt number `attempt` (1-based).
---@param attempt integer
---@param opts Lib.Patterns.RetryBackoff.Opts|nil
---@return number
function M.delay(attempt, opts)
  opts = opts or {}
  local d = (opts.base_ms or 100) * (opts.factor or 2) ^ (attempt - 1)
  d = math.min(d, opts.max_ms or 10000)
  if opts.jitter then
    d = d * (0.5 + math.random() * 0.5)
  end
  return d
end

---@param task fun(attempt: integer, done: fun(ok: boolean, value_or_err: any))
---@param opts Lib.Patterns.RetryBackoff.Opts|nil
function M.run(task, opts)
  opts = opts or {}
  local max = opts.max_attempts or 5
  local sleep = opts.sleep or function(ms, cb)
    vim.defer_fn(cb, ms)
  end

  local function finish(ok, res, attempts)
    if opts.on_done then
      opts.on_done(ok, res, attempts)
    end
  end

  local function attempt_n(n)
    local settled = false
    local function done(ok, res)
      if settled then
        return
      end
      settled = true
      if ok then
        return finish(true, res, n)
      end
      local retry_ok = n < max and (not opts.should_retry or opts.should_retry(res, n))
      if not retry_ok then
        return finish(false, res, n)
      end
      sleep(M.delay(n, opts), function()
        attempt_n(n + 1)
      end)
    end
    local ok, err = pcall(task, n, done)
    if not ok then
      done(false, err)
    end
  end

  attempt_n(1)
end

return M
