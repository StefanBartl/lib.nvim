-- TESTS/async_map_limit_spec.lua — lib.nvim.async.map_limit
--
-- Workers are completed by hand (their `done` callbacks are collected and
-- called from the spec body), so every ordering below is exact and no spec
-- depends on a timer. The one exception is the final integration check with
-- real `git` processes.

return function(H)
  local async = require("lib.nvim.async")
  local git = require("lib.nvim.git")

  local function wait_for(pred)
    vim.wait(10000, pred, 10)
    return pred()
  end

  --- Run map_limit with workers that park until the spec completes them.
  ---@return table ctx
  local function parked(n, limit, opts)
    local ctx =
      { started = {}, dones = {}, finished = nil, finish_count = 0, in_flight = 0, peak = 0 }
    local items = {}
    for i = 1, n do
      items[i] = "item" .. i
    end
    ctx.handle = async.map_limit(items, limit, function(item, index, done)
      ctx.started[#ctx.started + 1] = index
      ctx.in_flight = ctx.in_flight + 1
      ctx.peak = math.max(ctx.peak, ctx.in_flight)
      ctx.dones[index] = function(...)
        ctx.in_flight = ctx.in_flight - 1
        done(...)
      end
      assert(item == "item" .. index)
    end, function(results, errors, stopped)
      ctx.finish_count = ctx.finish_count + 1
      ctx.finished = { results = results, errors = errors, stopped = stopped }
    end, opts)
    return ctx
  end

  -- ── the limit holds, and a finished worker frees a slot immediately ─────
  local ctx = parked(5, 2)
  H.eq(table.concat(ctx.started, ","), "1,2", "map_limit: only `limit` workers start at first")
  ctx.dones[2]("r2")
  H.eq(table.concat(ctx.started, ","), "1,2,3", "map_limit: a finished worker starts the next item")
  ctx.dones[3]("r3")
  H.eq(table.concat(ctx.started, ","), "1,2,3,4", "map_limit: ... and again")
  ctx.dones[1]("r1")
  ctx.dones[4]("r4")
  H.eq(ctx.finished, nil, "map_limit: not finished while one item is still running")
  ctx.dones[5]("r5")
  H.eq(ctx.finished, nil, "map_limit: on_done is scheduled, never called synchronously")
  H.ok(
    wait_for(function()
      return ctx.finished ~= nil
    end),
    "map_limit: on_done fires once everything finished"
  )
  H.eq(ctx.peak, 2, "map_limit: never more than `limit` in flight")
  H.eq(ctx.finish_count, 1, "map_limit: on_done fires exactly once")
  H.eq(ctx.finished.stopped, false, "map_limit: not stopped")
  H.eq(
    table.concat(ctx.finished.results, ","),
    "r1,r2,r3,r4,r5",
    "map_limit: results are in item order, not completion order"
  )
  H.eq(next(ctx.finished.errors), nil, "map_limit: no errors")

  -- ── errors travel with their item ───────────────────────────────────────
  local err_ctx = parked(3, 3)
  err_ctx.dones[2](nil, "no luck")
  err_ctx.dones[1]("fine")
  err_ctx.dones[3]("also fine")
  wait_for(function()
    return err_ctx.finished ~= nil
  end)
  H.eq(err_ctx.finished.errors[2], "no luck", "map_limit: an item's error is in errors[i]")
  H.eq(err_ctx.finished.results[2], nil, "map_limit: ... and it has no result")
  H.eq(err_ctx.finished.results[3], "also fine", "map_limit: the other items are unaffected")

  -- ── a second `done` is ignored, a worker that never finishes is its own problem ──
  local twice = parked(2, 2)
  twice.dones[1]("first")
  twice.dones[1]("second")
  H.eq(twice.finished, nil, "map_limit: a repeated done does not count as a second item")
  twice.dones[2]("x")
  wait_for(function()
    return twice.finished ~= nil
  end)
  H.eq(twice.finished.results[1], "first", "map_limit: ... and does not overwrite the result")

  -- ── workers that finish synchronously: no recursion, no stack overflow ──
  local sync_calls, sync_result = 0, nil
  local many = {}
  for i = 1, 20000 do
    many[i] = i
  end
  async.map_limit(many, 3, function(item, _, done)
    sync_calls = sync_calls + 1
    done(item * 2)
  end, function(results)
    sync_result = results
  end)
  H.ok(
    wait_for(function()
      return sync_result ~= nil
    end),
    "map_limit: 20000 synchronous workers complete"
  )
  H.eq(sync_calls, 20000, "map_limit: every item runs exactly once")
  H.eq(sync_result[1], 2, "map_limit: synchronous results, first")
  H.eq(sync_result[20000], 40000, "map_limit: ... and last")

  -- ── a throwing worker is that item's error, not the run's ───────────────
  local thrown
  async.map_limit({ 1, 2, 3 }, 2, function(item, _, done)
    if item == 2 then
      error("boom", 0)
    end
    done(item)
  end, function(results, errors)
    thrown = { results = results, errors = errors }
  end)
  H.ok(
    wait_for(function()
      return thrown ~= nil
    end),
    "map_limit: a throwing worker does not stall the run"
  )
  H.eq(thrown.errors[2], "boom", "map_limit: ... its error is recorded")
  H.eq(thrown.results[1], 1, "map_limit: ... and the other items completed")
  H.eq(thrown.results[3], 3, "map_limit: ... all of them")

  -- A worker that completes and *then* throws does not count twice.
  local after_throw
  async.map_limit({ 1 }, 1, function(item, _, done)
    done(item)
    error("late", 0)
  end, function(results, errors)
    after_throw = { results = results, errors = errors }
  end)
  wait_for(function()
    return after_throw ~= nil
  end)
  H.eq(after_throw.results[1], 1, "map_limit: done before a throw keeps its result")
  H.eq(after_throw.errors[1], nil, "map_limit: ... and the late throw is not an error of the item")

  -- ── limit is clamped ────────────────────────────────────────────────────
  for _, bad in ipairs({ 0, -4, "x" }) do
    local c = parked(3, bad)
    H.eq(#c.started, 1, "map_limit: limit " .. tostring(bad) .. " runs one at a time")
    c.handle.stop()
  end
  H.eq(#parked(5, 2.9).started, 2, "map_limit: a fractional limit is floored")
  H.eq(#parked(5, "3").started, 3, "map_limit: a numeric string works")
  H.eq(#parked(2, 10).started, 2, "map_limit: a limit above the item count just starts all")

  -- ── empty input ─────────────────────────────────────────────────────────
  local empty
  async.map_limit({}, 4, function() end, function(results, errors, stopped)
    empty = { results = results, errors = errors, stopped = stopped }
  end)
  H.eq(empty, nil, "map_limit: even an empty run reports asynchronously")
  H.ok(
    wait_for(function()
      return empty ~= nil
    end),
    "map_limit: an empty run reports"
  )
  H.eq(#empty.results, 0, "map_limit: ... no results")
  H.eq(empty.stopped, false, "map_limit: ... and was not stopped")

  -- ── progress ────────────────────────────────────────────────────────────
  local progress = {}
  local prog_ctx = parked(3, 3, {
    on_progress = function(count, total, index, result, err)
      progress[#progress + 1] = ("%d/%d#%d=%s|%s"):format(
        count,
        total,
        index,
        result,
        tostring(err)
      )
    end,
  })
  prog_ctx.dones[3]("c")
  prog_ctx.dones[1](nil, "bad")
  prog_ctx.dones[2]("b")
  wait_for(function()
    return prog_ctx.finished ~= nil
  end)
  H.eq(
    table.concat(progress, " "),
    "1/3#3=c|nil 2/3#1=nil|bad 3/3#2=b|nil",
    "map_limit: on_progress runs after every item, in completion order, before on_done"
  )

  -- ── stop ────────────────────────────────────────────────────────────────
  local stops = {}
  local stopped_run
  local s_calls = {}
  local s_handle = async.map_limit({ 1, 2, 3, 4 }, 2, function(item, _, done)
    s_calls[#s_calls + 1] = item
    stops[item] = { done = done, stopped = false }
    return {
      stop = function()
        stops[item].stopped = true
      end,
    }
  end, function(results, errors, stopped)
    stopped_run =
      { results = results, errors = errors, stopped = stopped, n = (stopped_run or {}).n }
    stopped_run.n = (stopped_run.n or 0) + 1
  end)
  stops[1].done("one")
  s_handle.stop()
  H.eq(stops[2].stopped, true, "map_limit stop: a worker still in flight is stopped")
  H.eq(stops[1].stopped, false, "map_limit stop: ... a finished one is left alone")
  H.eq(stops[3] and stops[3].stopped, true, "map_limit stop: the worker started after item 1 too")
  H.ok(
    wait_for(function()
      return stopped_run ~= nil
    end),
    "map_limit stop: on_done fires"
  )
  H.eq(stopped_run.stopped, true, "map_limit stop: ... with stopped = true")
  H.eq(stopped_run.results[1], "one", "map_limit stop: ... and the results so far")
  stops[2].done("late")
  stops[3].done("late")
  s_handle.stop()
  vim.wait(50, function()
    return false
  end, 10)
  H.eq(stopped_run.n, 1, "map_limit stop: on_done fires exactly once, a late done changes nothing")
  H.eq(stopped_run.results[2], nil, "map_limit stop: a late result is discarded")
  H.eq(#s_calls, 3, "map_limit stop: no further worker starts after stop")

  -- stop() after the run finished is a no-op
  local finished_ctx = parked(1, 1)
  finished_ctx.dones[1]("x")
  wait_for(function()
    return finished_ctx.finished ~= nil
  end)
  finished_ctx.handle.stop()
  vim.wait(30, function()
    return false
  end, 10)
  H.eq(finished_ctx.finish_count, 1, "map_limit stop: after the run finished it does nothing")
  H.eq(finished_ctx.finished.stopped, false, "map_limit stop: ... and the run stays not-stopped")

  -- a handle without a stop function is tolerated
  local odd = async.map_limit({ 1 }, 1, function()
    return { not_a_stop = true }
  end, function() end)
  H.eq(pcall(odd.stop), true, "map_limit stop: a worker handle without stop() is tolerated")

  -- A worker handle whose stop() reports back through `done` (a cancelled
  -- request, a timer) must not count as a normal completion that starts the
  -- next item: the run is already over when it is stopped.
  local re_started, re_result = 0, nil
  local re_handle = async.map_limit({ 1, 2, 3, 4 }, 2, function(_, _, done)
    re_started = re_started + 1
    return {
      stop = function()
        done(nil, "cancelled")
      end,
    }
  end, function(results, errors, stopped)
    re_result = { results = results, errors = errors, stopped = stopped }
  end)
  re_handle.stop()
  H.ok(
    wait_for(function()
      return re_result ~= nil
    end),
    "map_limit stop: a stop() that calls done synchronously still ends the run"
  )
  H.eq(re_result.stopped, true, "map_limit stop: ... as stopped, not as completed")
  H.eq(re_started, 2, "map_limit stop: ... without starting a further worker")

  -- A worker that stops the run while it is starting returns a handle nobody
  -- else will ever stop: map_limit stops it.
  local leak_done, leak_stops, leak_handle = nil, 0, nil
  leak_handle = async.map_limit({ 1, 2 }, 1, function(item, _, done)
    if item == 1 then
      leak_done = done
      return nil
    end
    leak_handle.stop()
    return {
      stop = function()
        leak_stops = leak_stops + 1
      end,
    }
  end, function() end)
  leak_done("first")
  H.eq(leak_stops, 1, "map_limit stop: a handle returned after the run was stopped is stopped too")

  -- a limit that is NaN falls back to one at a time instead of starting nothing
  local nan_result
  async.map_limit({ 1, 2 }, 0 / 0, function(item, _, done)
    done(item)
  end, function(results)
    nan_result = results
  end)
  H.ok(
    wait_for(function()
      return nan_result ~= nil
    end),
    "map_limit: a NaN limit still runs"
  )
  H.eq(nan_result[2], 2, "map_limit: ... every item")

  -- the thrown value is passed on as it was, not flattened to a string
  local thrown_value
  async.map_limit({ 1 }, 1, function()
    error({ code = 7 })
  end, function(_, errors)
    thrown_value = errors[1]
  end)
  wait_for(function()
    return thrown_value ~= nil
  end)
  H.eq(type(thrown_value), "table", "map_limit: a thrown table stays a table")
  H.eq(thrown_value.code, 7, "map_limit: ... with its content")

  -- ── argument checks are programming errors ──────────────────────────────
  H.eq(pcall(async.map_limit, "nope", 1, function() end, function() end), false, "items: a list")
  H.eq(pcall(async.map_limit, {}, 1, nil, function() end), false, "worker: a function")
  H.eq(pcall(async.map_limit, {}, 1, function() end, nil), false, "on_done: a function")

  -- ── with real processes: the worker returns the git handle ──────────────
  local git_done
  async.map_limit({ "a", "b", "c" }, 2, function(_, _, done)
    return git.run_async({ "--version" }, nil, function(res)
      done(res.ok and vim.trim(res.stdout) or nil, not res.ok and res.stderr or nil)
    end)
  end, function(results, errors)
    git_done = { results = results, errors = errors }
  end)
  H.ok(
    wait_for(function()
      return git_done ~= nil
    end),
    "map_limit + git.run_async: the run completes"
  )
  H.ok(
    git_done.results[1] and git_done.results[1]:find("git version", 1, true),
    "git: first result"
  )
  H.ok(git_done.results[3] and git_done.results[3]:find("git version", 1, true), "git: last result")
  H.eq(next(git_done.errors), nil, "map_limit + git.run_async: no errors")
end
