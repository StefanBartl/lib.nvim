-- docs/TESTS/mutate_spec.lua — lib.nvim.cross.fs.mutate
--
-- The interesting behavior here (retry on a transient Windows sharing
-- error, escalating backoff, on_retry hooks) can't wait on a *real*
-- EPERM/EACCES/EBUSY lock in a headless test without being slow and
-- flaky. M.retry takes an arbitrary `op` function though, so a lock is
-- simulated by an op that returns a transient-looking error N times
-- before succeeding -- deterministic, and it exercises the exact same
-- retry/backoff/on_retry code path a real Windows sharing violation would.

return function(H)
  local eq, ok = H.eq, H.ok

  local mutate = require("lib.nvim.cross.fs.mutate")

  -- ------------------------------------------------------------ M.retry

  -- Succeeds first try: op called once, no retry machinery engaged.
  do
    local calls = 0
    local result_ok, result_err = mutate.retry(function()
      calls = calls + 1
      return true, nil
    end, { attempts = 3, backoff_ms = 1 })
    eq(result_ok, true, "retry: immediate success reports ok")
    eq(result_err, nil, "retry: immediate success has no error")
    eq(calls, 1, "retry: immediate success calls op exactly once")
  end

  -- Simulated lock: fails with a transient error twice, then succeeds --
  -- the shape of "an AV scanner briefly held the handle, then let go".
  do
    local calls = 0
    local retry_log = {}
    local result_ok, result_err = mutate.retry(function()
      calls = calls + 1
      if calls <= 2 then
        return false, "EBUSY: resource busy or locked"
      end
      return true, nil
    end, {
      attempts = 5,
      backoff_ms = 1,
      on_retry = function(attempt, err)
        retry_log[#retry_log + 1] = { attempt = attempt, err = err }
      end,
    })
    eq(result_ok, true, "retry: succeeds once the simulated lock clears")
    eq(result_err, nil, "retry: no error once it eventually succeeds")
    eq(calls, 3, "retry: stops calling op as soon as it succeeds (2 failures + 1 success)")
    eq(#retry_log, 2, "retry: on_retry fires once per failed attempt, not on the final success")
    eq(retry_log[1].attempt, 1, "retry: on_retry reports the 1-based attempt number")
    eq(retry_log[2].attempt, 2, "retry: on_retry reports each subsequent attempt")
  end

  -- Simulated permanent lock: transient error on every attempt -> gives up
  -- after `attempts`, reporting the last attempt's error.
  do
    local calls = 0
    local result_ok, result_err = mutate.retry(function()
      calls = calls + 1
      return false, ("EPERM: attempt %d"):format(calls)
    end, { attempts = 3, backoff_ms = 1 })
    eq(result_ok, false, "retry: exhausting all attempts reports failure")
    eq(calls, 3, "retry: tries exactly `attempts` times, no more")
    eq(result_err, "EPERM: attempt 3", "retry: reports the FINAL attempt's error, not the first")
  end

  -- A non-transient error (e.g. the path genuinely does not exist) must
  -- not be retried at all -- retrying can't fix "file not found", and
  -- burning `attempts * backoff` on it would just make every ordinary
  -- error slow.
  do
    local calls = 0
    local result_ok, result_err = mutate.retry(function()
      calls = calls + 1
      return false, "ENOENT: no such file or directory"
    end, { attempts = 5, backoff_ms = 1 })
    eq(result_ok, false, "retry: a non-transient error still fails")
    eq(calls, 1, "retry: a non-transient error is NOT retried, even with attempts > 1")
    eq(
      result_err,
      "ENOENT: no such file or directory",
      "retry: the non-transient error passes through unchanged"
    )
  end

  -- on_retry is never called when there's nothing to retry (immediate
  -- success, or a non-transient error on the first try).
  do
    local retry_fired = false
    mutate.retry(function()
      return false, "ENOENT: gone"
    end, {
      attempts = 3,
      backoff_ms = 1,
      on_retry = function()
        retry_fired = true
      end,
    })
    eq(retry_fired, false, "retry: on_retry does not fire for a non-transient error")
  end

  -- `defaults` exists and is a sane baseline the primitives fall back to
  -- when a call site passes no opts at all.
  ok(
    type(mutate.defaults.attempts) == "number" and mutate.defaults.attempts >= 1,
    "defaults.attempts is a positive number"
  )
  ok(
    type(mutate.defaults.backoff_ms) == "number" and mutate.defaults.backoff_ms > 0,
    "defaults.backoff_ms is a positive number"
  )

  -- --------------------------------------------------- real-file smoke tests
  --
  -- The four primitives are thin `retry(function() return uv().fs_x(...) end)`
  -- wrappers; the retry logic above is what's actually load-bearing, but a
  -- quick real-filesystem pass confirms the wiring (right libuv call, right
  -- (ok, err) shape) is intact end to end.

  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")

  local src = dir .. "/a.txt"
  local f = assert(io.open(src, "w"))
  f:write("hello")
  f:close()

  local copy_ok = mutate.copy_file(src, dir .. "/b.txt")
  eq(copy_ok, true, "copy_file: copies an existing file")
  local cf = assert(io.open(dir .. "/b.txt", "r"))
  eq(cf:read("*a"), "hello", "copy_file: content matches the source")
  cf:close()

  local rename_ok = mutate.rename_file(dir .. "/b.txt", dir .. "/c.txt")
  eq(rename_ok, true, "rename_file: renames an existing file")
  eq((vim.uv or vim.loop).fs_stat(dir .. "/b.txt"), nil, "rename_file: old path no longer exists")
  ok((vim.uv or vim.loop).fs_stat(dir .. "/c.txt") ~= nil, "rename_file: new path exists")

  local delete_ok = mutate.delete_file(dir .. "/c.txt")
  eq(delete_ok, true, "delete_file: deletes an existing file")
  eq((vim.uv or vim.loop).fs_stat(dir .. "/c.txt"), nil, "delete_file: path is gone")

  local delete_missing_ok, delete_missing_err = mutate.delete_file(dir .. "/does-not-exist.txt")
  eq(delete_missing_ok, false, "delete_file: a missing path fails")
  ok(delete_missing_err ~= nil, "delete_file: a missing path reports an error")

  local nested = dir .. "/x/y/z"
  local mkdirp_ok = mutate.mkdir_p(nested)
  eq(mkdirp_ok, true, "mkdir_p: creates a nested directory tree")
  eq(vim.fn.isdirectory(nested), 1, "mkdir_p: the deepest directory exists")

  local mkdirp_again_ok = mutate.mkdir_p(nested)
  eq(mkdirp_again_ok, true, "mkdir_p: re-creating an already-existing directory is still ok")
end
