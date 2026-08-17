-- docs/TESTS/async_spec.lua — lib.nvim.async
--
-- Real libuv calls and real coroutine suspension, no mocking: the awaited
-- work is an actual `uv.new_timer()` round-trip through the event loop, so
-- a test that passes proves control really left and came back, not that a
-- callback happened to be invoked inline.

return function(H)
  local eq, ok = H.eq, H.ok

  local async = require("lib.nvim.async")
  local uv = vim.uv or vim.loop

  ---Await-able sleep: yields until a real uv timer fires.
  ---@param ms integer
  local function sleep(ms)
    async.await(function(resume)
      local timer = uv.new_timer()
      timer:start(ms, 0, function()
        timer:stop()
        timer:close()
        resume()
      end)
    end)
  end

  ---Run `fn` under async.run and block (via vim.wait) until on_done fires.
  ---Returns whatever on_done received.
  ---@param fn fun(): ...
  ---@param opts? Lib.Async.RunOpts
  local function run_sync(fn, opts)
    local finished, results = false, nil
    async.run(fn, function(...)
      results = { n = select("#", ...), ... }
      finished = true
    end, opts)
    ok(
      vim.wait(5000, function()
        return finished
      end, 5),
      "run_sync: the coroutine finished within its timeout"
    )
    return results or { n = 0 }
  end

  -- ------------------------------------------------------------- await/run

  do
    local results = run_sync(function()
      sleep(10)
      return "after-await"
    end)
    eq(results[1], "after-await", "run: on_done receives the body's return value")
  end

  -- Multiple return values survive, embedded nil included (the LuaJIT
  -- table.pack/unpack fallback path).
  do
    local results = run_sync(function()
      sleep(1)
      return 1, nil, 3
    end)
    eq(results.n, 3, "run: arity preserved across an embedded nil")
    eq(results[1], 1, "run: first return value")
    eq(results[2], nil, "run: embedded nil survives")
    eq(results[3], 3, "run: third return value")
  end

  -- await returns whatever resume was handed.
  do
    local results = run_sync(function()
      local a, b = async.await(function(resume)
        resume("x", "y")
      end)
      return a .. b
    end)
    eq(results[1], "xy", "await: returns resume's arguments")
  end

  -- A body that never awaits still completes (the coroutine dies on the
  -- very first resume, so `run` must handle that without yielding).
  do
    local results = run_sync(function()
      return "no-await"
    end)
    eq(results[1], "no-await", "run: a body with no await at all still completes")
  end

  -- on_done is optional.
  do
    local reached = false
    async.run(function()
      sleep(1)
      reached = true
    end)
    vim.wait(2000, function()
      return reached
    end, 5)
    ok(reached, "run: on_done is optional")
  end

  -- ------------------------------------------------------------ error path

  -- An error inside the body must not propagate to the caller (its stack is
  -- gone) -- it goes to opts.on_error instead.
  do
    local caught
    async.run(
      function()
        sleep(1)
        error("boom")
      end,
      nil,
      {
        on_error = function(err)
          caught = err
        end,
      }
    )
    vim.wait(2000, function()
      return caught ~= nil
    end, 5)
    ok(caught ~= nil, "run: on_error fires for an error raised after an await")
    ok(tostring(caught):match("boom") ~= nil, "run: ... carrying the original message")
  end

  -- An error raised before the first await takes the same path (the failure
  -- happens on the synchronous initial resume, not inside a uv callback).
  do
    local caught
    async.run(
      function()
        error("immediate boom")
      end,
      nil,
      {
        on_error = function(err)
          caught = err
        end,
      }
    )
    ok(caught ~= nil, "run: on_error fires for an error raised before any await")
    ok(tostring(caught):match("immediate boom") ~= nil, "run: ... with its message")
  end

  -- on_done must not run when the body errored.
  do
    local done_ran, errored = false, false
    async.run(function()
      sleep(1)
      error("nope")
    end, function()
      done_ran = true
    end, {
      on_error = function()
        errored = true
      end,
    })
    vim.wait(2000, function()
      return errored
    end, 5)
    vim.wait(200, function()
      return false
    end, 10)
    ok(errored, "run: the error path ran")
    ok(not done_ran, "run: on_done is skipped when the body errored")
  end

  -- ------------------------------------------------------------------ wrap

  do
    local fs_stat = async.wrap(uv.fs_stat, 2)
    local tmp = vim.fn.tempname()
    vim.fn.writefile({ "content" }, tmp)

    local results = run_sync(function()
      local err, stat = fs_stat(tmp)
      return err, stat and stat.type
    end)
    eq(results[1], nil, "wrap: no error for a real existing file")
    eq(results[2], "file", "wrap: the uv callback's values come back from the await")

    os.remove(tmp)
  end

  -- wrap on a function with optional args: the callback still has to land in
  -- slot `argc` even though fewer arguments were passed.
  do
    local probe = async.wrap(function(a, b, cb)
      cb(a, b)
    end, 3)

    local results = run_sync(function()
      return probe("only-a")
    end)
    eq(results[1], "only-a", "wrap: passed argument arrives")
    eq(results[2], nil, "wrap: the omitted argument stays nil, callback still in slot argc")
  end

  -- ------------------------------------------------------------- Semaphore

  -- With one permit, two coroutines must not overlap: the second's critical
  -- section can only start after the first released.
  do
    local sem = async.Semaphore.new(1)
    local order, running, max_running = {}, 0, 0

    local function worker(name)
      return function()
        sem:acquire()
        running = running + 1
        max_running = math.max(max_running, running)
        order[#order + 1] = name .. ":in"
        sleep(15)
        order[#order + 1] = name .. ":out"
        running = running - 1
        sem:release()
      end
    end

    local done_count = 0
    local function on_done()
      done_count = done_count + 1
    end
    async.run(worker("a"), on_done)
    async.run(worker("b"), on_done)

    vim.wait(5000, function()
      return done_count == 2
    end, 5)

    eq(done_count, 2, "Semaphore: both coroutines completed")
    eq(max_running, 1, "Semaphore(1): the critical sections never overlapped")
    eq(
      table.concat(order, ","),
      "a:in,a:out,b:in,b:out",
      "Semaphore(1): the second waiter only enters after the first released"
    )
  end

  -- Permits above the contention level never block.
  do
    local sem = async.Semaphore.new(2)
    local results = run_sync(function()
      sem:acquire()
      sem:acquire()
      sem:release()
      sem:release()
      return "uncontended"
    end)
    eq(results[1], "uncontended", "Semaphore(2): two acquires in a row do not deadlock")
  end

  -- Releasing with nobody waiting gives the permit back to the count.
  do
    local sem = async.Semaphore.new(1)
    local results = run_sync(function()
      sem:acquire()
      sem:release()
      sem:acquire() -- must succeed: the permit went back
      sem:release()
      return "recycled"
    end)
    eq(results[1], "recycled", "Semaphore: an uncontended release restores the permit")
  end

  -- --------------------------------------------------------------- Condvar

  do
    local cv = async.Condvar.new()
    local woken = false

    async.run(function()
      cv:wait()
      woken = true
    end)

    -- Let the waiter actually reach its wait() before notifying.
    vim.wait(100, function()
      return false
    end, 10)
    ok(not woken, "Condvar: the waiter is still suspended before any notify")

    cv:notify_one()
    vim.wait(2000, function()
      return woken
    end, 5)
    ok(woken, "Condvar: notify_one wakes the waiter")
  end

  -- notify_all wakes every waiter; notify_one only the longest-waiting.
  do
    local cv = async.Condvar.new()
    local woken = 0

    for _ = 1, 3 do
      async.run(function()
        cv:wait()
        woken = woken + 1
      end)
    end
    vim.wait(100, function()
      return false
    end, 10)

    cv:notify_one()
    vim.wait(500, function()
      return woken >= 1
    end, 5)
    eq(woken, 1, "Condvar: notify_one wakes exactly one waiter")

    cv:notify_all()
    vim.wait(2000, function()
      return woken >= 3
    end, 5)
    eq(woken, 3, "Condvar: notify_all wakes the rest")
  end

  -- Notifying with nobody waiting is a no-op, not an error.
  do
    local cv = async.Condvar.new()
    cv:notify_one()
    cv:notify_all()
    ok(true, "Condvar: notifying an empty waiter list does not raise")
  end
end
