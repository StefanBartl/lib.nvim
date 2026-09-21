-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/watch_spec.lua — lib.nvim.fs.watch
--
-- Real fs_event, real filesystem, no mocking (same philosophy as
-- curl_spec.lua's real TCP server): a temp directory is watched, a real
-- file inside it is written to, and the test polls via vim.wait for the
-- debounced callback instead of asserting on a fixed delay.
--
-- Every watcher is ARMED before the change under test is made. `start()`
-- returns as soon as libuv accepted the handle, not once the OS backend is
-- delivering: on macOS libuv registers the FSEvents stream from its own
-- CFRunLoop thread, so a write made right after `start()` can happen before
-- the stream exists and is then never reported. Racing that window is what
-- made "on_change fires after a real file write" flake on macos-latest. The
-- handshake below is a readiness poll, not a sleep: probe writes repeat until
-- the watcher reports one, so a healthy backend costs one debounce period and
-- a backend that never delivers fails loudly after `ARM_TIMEOUT_MS`.

return function(H)
  local eq, ok = H.eq, H.ok

  local watch = require("lib.nvim.fs.watch")
  local uv = vim.uv or vim.loop

  local PROBE = "arm-probe.txt"
  local ARM_TIMEOUT_MS = 10000
  local EVENT_TIMEOUT_MS = 5000

  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")

  ---@return number
  local function now_ms()
    return uv.hrtime() / 1e6
  end

  ---Last path component of a reported filename. Not every backend reports a
  ---bare name: on Windows a watched directory reached through a short (8.3)
  ---path such as `C:\Users\RUNNER~1\...` -- what `tempname()` returns on
  ---GitHub's runners -- comes back as `\0\arm-probe.txt`, directory prefix
  ---included. The last component is the file on every platform.
  ---@param filename string|nil
  ---@return string|nil
  local function basename(filename)
    return filename and filename:match("[^/\\]+$")
  end

  ---How many recorded callbacks carried `name`.
  ---@param seen string[]
  ---@param name string
  ---@return integer
  local function count_of(seen, name)
    local n = 0
    for _, filename in ipairs(seen) do
      if filename == name then
        n = n + 1
      end
    end
    return n
  end

  ---Start a watcher on `dir` and return it only after it has reported a probe
  ---write, i.e. once the backend is provably delivering events. Probe events
  ---never reach `seen`; everything else does, by filename.
  ---@param dir string
  ---@param debounce_ms integer
  ---@param seen string[] # receives the filename of every non-probe callback
  ---@return Lib.Fs.Watch.Handle
  local function armed_watch(dir, debounce_ms, seen)
    local armed = false
    local handle, err = watch.start(dir, function(_, filename, _)
      local name = basename(filename)
      if name == PROBE then
        armed = true
      else
        seen[#seen + 1] = name
      end
    end, { debounce_ms = debounce_ms })
    ok(handle ~= nil, "watch.start: returns a handle")
    eq(err, nil, "watch.start: no error on a real, existing directory")

    -- vim.wait evaluates the condition every few ms; a write per evaluation
    -- would keep resetting the debounce and starve the very callback awaited.
    -- One probe per three debounce periods leaves room for it to fire.
    local retry_ms = math.max(debounce_ms * 3, 100)
    local last_probe = -math.huge
    local n = 0
    ok(
      vim.wait(ARM_TIMEOUT_MS, function()
        if armed then
          return true
        end
        if now_ms() - last_probe >= retry_ms then
          last_probe = now_ms()
          n = n + 1
          vim.fn.writefile({ "probe " .. n }, dir .. "/" .. PROBE)
        end
        return false
      end, 10),
      "watch: watcher reports a probe write (backend armed)"
    )
    return handle
  end

  -- ------------------------------------------------------- basic callback

  local basic_seen = {}
  local handle = armed_watch(tmp, 50, basic_seen)

  vim.fn.writefile({ "changed" }, tmp .. "/watched.txt")
  ok(
    vim.wait(EVENT_TIMEOUT_MS, function()
      return count_of(basic_seen, "watched.txt") >= 1
    end, 20),
    "watch: on_change fires after a real file write"
  )

  handle.stop()

  -- --------------------------------------------------- debounce coalescing

  -- 250 ms, not tighter: the three writes below must land well inside one
  -- window even on a loaded runner.
  local coalesce_seen = {}
  local coalesce_handle = armed_watch(tmp, 250, coalesce_seen)

  -- Three writes in quick succession, well inside the debounce window —
  -- should settle into (at most) one callback, not three.
  local coalesced = tmp .. "/coalesced.txt"
  vim.fn.writefile({ "a" }, coalesced)
  vim.fn.writefile({ "ab" }, coalesced)
  vim.fn.writefile({ "abc" }, coalesced)

  -- Give the debounce window time to elapse and fire.
  vim.wait(EVENT_TIMEOUT_MS, function()
    return count_of(coalesce_seen, "coalesced.txt") >= 1
  end, 20)
  -- ... then confirm nothing further trickles in afterward (two windows).
  vim.wait(500, function()
    return false
  end, 20)

  local coalesce_calls = count_of(coalesce_seen, "coalesced.txt")
  ok(coalesce_calls >= 1, "watch: rapid writes still produce at least one callback")
  ok(coalesce_calls < 3, "watch: rapid writes coalesce into fewer callbacks than writes")

  coalesce_handle.stop()
  coalesce_handle.stop() -- idempotent: calling stop() twice must not error

  -- ------------------------------------------------------------- stop()

  -- Armed first, so "no callback after stop" is not vacuously true on a
  -- watcher that never delivered anything in the first place.
  local stop_seen = {}
  local stop_handle = armed_watch(tmp, 50, stop_seen)
  stop_handle.stop()

  vim.fn.writefile({ "after stop" }, tmp .. "/after-stop.txt")
  vim.wait(300, function()
    return false
  end, 20)
  eq(count_of(stop_seen, "after-stop.txt"), 0, "watch: stop() prevents any further callback")
end
