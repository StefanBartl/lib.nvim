-- TESTS/watch_spec.lua — lib.nvim.fs.watch
--
-- Real fs_event, real filesystem, no mocking (same philosophy as
-- curl_spec.lua's real TCP server): a temp directory is watched, a real
-- file inside it is written to, and the test polls via vim.wait for the
-- debounced callback instead of asserting on a fixed delay.

return function(H)
  local eq, ok = H.eq, H.ok

  local watch = require("lib.nvim.fs.watch")

  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")
  local target = tmp .. "/watched.txt"
  vim.fn.writefile({ "initial" }, target)

  -- ------------------------------------------------------- basic callback

  local calls = 0
  local handle, err = watch.start(tmp, function(_, _, _)
    calls = calls + 1
  end, { debounce_ms = 50 })

  ok(handle ~= nil, "watch.start: returns a handle")
  eq(err, nil, "watch.start: no error on a real, existing directory")

  vim.fn.writefile({ "changed" }, target)
  ok(
    vim.wait(2000, function()
      return calls >= 1
    end, 20),
    "watch: on_change fires after a real file write"
  )

  handle.stop()

  -- --------------------------------------------------- debounce coalescing

  local coalesce_calls = 0
  local coalesce_handle = watch.start(tmp, function()
    coalesce_calls = coalesce_calls + 1
  end, { debounce_ms = 150 })

  -- Three writes in quick succession, well inside the debounce window —
  -- should settle into (at most) one callback, not three.
  vim.fn.writefile({ "a" }, target)
  vim.fn.writefile({ "ab" }, target)
  vim.fn.writefile({ "abc" }, target)

  -- Give the debounce window time to elapse and fire.
  vim.wait(1000, function()
    return coalesce_calls >= 1
  end, 20)
  -- ... then confirm nothing further trickles in afterward.
  vim.wait(300, function()
    return false
  end, 20)

  ok(coalesce_calls >= 1, "watch: rapid writes still produce at least one callback")
  ok(coalesce_calls < 3, "watch: rapid writes coalesce into fewer callbacks than writes")

  coalesce_handle.stop()
  coalesce_handle.stop() -- idempotent: calling stop() twice must not error

  -- ------------------------------------------------------------- stop()

  local after_stop_calls = 0
  local stop_handle = watch.start(tmp, function()
    after_stop_calls = after_stop_calls + 1
  end, { debounce_ms = 50 })
  stop_handle.stop()

  vim.fn.writefile({ "after stop" }, target)
  vim.wait(300, function()
    return false
  end, 20)
  eq(after_stop_calls, 0, "watch: stop() prevents any further callback")
end
