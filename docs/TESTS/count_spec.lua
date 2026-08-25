-- docs/TESTS/count_spec.lua — lib.nvim.count

return function(H)
  local eq, ok = H.eq, H.ok

  local count = require("lib.nvim.count")

  -- `vim.v.count` / `vim.v.count1` are read-only and only meaningful while a
  -- mapping is executing, so the reading helpers (`get`/`raw`/`given`/`clamp`)
  -- are exercised through a real keypress via `nvim_feedkeys`. Everything that
  -- repeats takes an explicit `count` in opts precisely so it stays testable
  -- without one.

  local function press(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
  end

  -- ------------------------------------------------------------ reading

  local seen = {}
  vim.keymap.set("n", "<Plug>(spec_count_read)", function()
    seen = {
      get = count.get(),
      raw = count.raw(),
      given = count.given(),
      clamp = count.clamp(1, 9),
    }
  end)
  vim.keymap.set("n", "gzs", "<Plug>(spec_count_read)")

  press("gzs")
  eq(seen.get, 1, "get() is 1 when no count was typed")
  eq(seen.raw, 0, "raw() is 0 when no count was typed")
  eq(seen.given, false, "given() is false when no count was typed")

  press("3gzs")
  eq(seen.get, 3, "get() returns the typed count")
  eq(seen.raw, 3, "raw() returns the typed count")
  eq(seen.given, true, "given() is true once a count was typed")
  eq(seen.clamp, 3, "clamp() passes an in-range count through")

  press("42gzs")
  eq(seen.clamp, 9, "clamp() caps an over-range count at max")

  vim.keymap.del("n", "gzs")
  vim.keymap.del("n", "<Plug>(spec_count_read)")

  -- ------------------------------------------------------------- times

  local runs = {}
  local ran = count.times(function(i)
    runs[#runs + 1] = i
  end, { count = 4 })
  eq(ran, 4, "times() runs once per count")
  eq(table.concat(runs, ","), "1,2,3,4", "times() passes the 1-based index")

  runs = {}
  ran = count.times(function(i)
    runs[#runs + 1] = i
    return i ~= 2 -- stop at the second iteration
  end, { count = 10 })
  eq(ran, 2, "times() stops early when fn returns false, reporting the real count")
  eq(#runs, 2, "times() does not call fn again after a false")

  local capped = 0
  ran = count.times(function()
    capped = capped + 1
  end, { count = 5000, max = 3 })
  eq(ran, 3, "times() honors an explicit max")
  eq(capped, 3, "times() does not run past max")

  ran = count.times(function() end, { count = 99999 })
  eq(ran, count.DEFAULT_MAX, "times() caps a fat-fingered count at DEFAULT_MAX")

  -- ------------------------------------------------------------- chain
  --
  -- The point of chain(): the next call must not fire until the caller signals
  -- the previous one completed. A driver that never advances must therefore
  -- leave exactly one call made.

  local calls = 0
  local advance_cb, abort_cb
  local unsubscribed = false

  local function subscribe(advance, abort)
    advance_cb, abort_cb = advance, abort
    return function()
      unsubscribed = true
    end
  end

  local chained = count.chain({
    action = function()
      calls = calls + 1
    end,
    subscribe = subscribe,
    count = 3,
  })
  ok(chained, "chain() reports that it set up a chain")
  eq(calls, 1, "chain() fires exactly one call up front, not the whole count")

  advance_cb()
  eq(calls, 2, "advance() releases the next call")
  advance_cb()
  eq(calls, 3, "advance() releases the last owed call")
  eq(unsubscribed, false, "chain() still listens for the final completion signal")

  advance_cb()
  eq(calls, 3, "no further call once the count is satisfied")
  ok(unsubscribed, "chain() unsubscribes after the last completion signal")

  -- count <= 1: no listener at all. `unsubscribed` is deliberately not reset
  -- here: this block asserts that nothing subscribes at all, so it never reads
  -- the flag, and resetting it was a dead store the next block overwrote.
  calls = 0
  local subscribed = false
  chained = count.chain({
    action = function()
      calls = calls + 1
    end,
    subscribe = function()
      subscribed = true
    end,
    count = 1,
  })
  eq(chained, false, "chain() reports a plain single call when count <= 1")
  eq(calls, 1, "chain() calls the action once")
  eq(subscribed, false, "chain() never subscribes without a count -- nothing to clean up")

  -- abort: the driven thing went away mid-chain.
  calls, unsubscribed = 0, false
  count.chain({
    action = function()
      calls = calls + 1
    end,
    subscribe = subscribe,
    count = 5,
  })
  eq(calls, 1, "chain() fires the first call")
  abort_cb()
  ok(unsubscribed, "abort() removes the listeners")
  advance_cb()
  eq(calls, 1, "a stale advance() after abort does not resurrect the chain")

  -- A subscribe that raises must not swallow the action, and must not fall
  -- back to an unpaced loop -- that loop is the bug chain() exists to prevent.
  calls = 0
  chained = count.chain({
    action = function()
      calls = calls + 1
    end,
    subscribe = function()
      error("driver exploded")
    end,
    count = 7,
  })
  eq(chained, false, "chain() reports no chain when subscribe raises")
  eq(calls, 1, "chain() runs the action exactly once when subscribe raises")

  -- A subscribe returning no unsubscribe is tolerated (nothing to remove).
  calls = 0
  count.chain({
    action = function()
      calls = calls + 1
    end,
    subscribe = function(advance)
      advance_cb = advance
      return nil
    end,
    count = 2,
  })
  advance_cb()
  advance_cb()
  eq(calls, 2, "chain() survives a subscribe that returns no unsubscribe")
end
