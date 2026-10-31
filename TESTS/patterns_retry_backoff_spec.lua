-- TESTS/patterns_retry_backoff_spec.lua — lib.nvim.patterns.retry_backoff
return function(H)
  local eq, ok = H.eq, H.ok
  local retry = require("lib.nvim.patterns.retry_backoff")

  eq(retry.delay(1, { base_ms = 100, factor = 2 }), 100, "delay: first")
  eq(retry.delay(3, { base_ms = 100, factor = 2 }), 400, "delay: grows")
  eq(retry.delay(10, { base_ms = 100, factor = 2, max_ms = 500 }), 500, "delay: capped")
  local j = retry.delay(2, { base_ms = 100, factor = 2, jitter = true })
  ok(j >= 100 and j <= 200, "delay: jitter stays within 50-100 percent")

  -- synchronous injected sleep: records the waits and continues at once
  local waits = {}
  local function sleep(ms, cb)
    waits[#waits + 1] = ms
    cb()
  end

  local result
  retry.run(function(attempt, done)
    done(attempt == 3, attempt == 3 and "yes" or "no")
  end, {
    max_attempts = 5,
    base_ms = 10,
    sleep = sleep,
    on_done = function(o, res, n)
      result = { o, res, n }
    end,
  })
  ok(result[1] and result[2] == "yes" and result[3] == 3, "succeeds on the third attempt")
  eq(table.concat(waits, ","), "10,20", "two waits with growing delay")

  waits, result = {}, nil
  retry.run(function(_, done)
    done(false, "always")
  end, {
    max_attempts = 3,
    base_ms = 5,
    sleep = sleep,
    on_done = function(o, res, n)
      result = { o, res, n }
    end,
  })
  ok(not result[1] and result[2] == "always" and result[3] == 3, "gives up after max_attempts")
  eq(#waits, 2, "no wait after the last attempt")

  waits, result = {}, nil
  retry.run(function(_, done)
    done(false, "fatal")
  end, {
    sleep = sleep,
    should_retry = function(err)
      return err ~= "fatal"
    end,
    on_done = function(o, res, n)
      result = { o, res, n }
    end,
  })
  ok(result[3] == 1 and #waits == 0, "should_retry can stop at once")

  result = nil
  retry.run(function()
    error("task blew up", 0)
  end, {
    max_attempts = 1,
    sleep = sleep,
    on_done = function(o, res)
      result = { o, res }
    end,
  })
  ok(not result[1] and result[2] == "task blew up", "a raising task counts as a failure")

  -- done called twice must not double-run
  local runs = 0
  retry.run(function(_, done)
    runs = runs + 1
    done(true, "a")
    done(false, "b")
  end, { sleep = sleep })
  eq(runs, 1, "second done() is ignored")
end
