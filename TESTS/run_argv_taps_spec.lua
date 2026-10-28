-- TESTS/run_argv_taps_spec.lua — lib.nvim.cross.run_argv: the output taps, keep_stdout and stop(signal, opts)
--
-- The child is a headless Neovim (no shell), so the same cases run on Windows, Linux and macOS.

return function(H)
  local eq, ok = H.eq, H.ok
  local run_argv = require("lib.nvim.cross.run_argv")
  local nvim = vim.v.progpath

  ---@param lines string[]
  ---@return string[] argv
  local function child(lines)
    local path = vim.fn.tempname() .. ".lua"
    vim.fn.writefile(lines, path)
    return { nvim, "--headless", "-u", "NONE", "-i", "NONE", "-l", path }
  end

  ---@param cmd string[]
  ---@param opts table
  ---@return table r `done, ok, out, code, err, signal`
  local function run(cmd, opts)
    local r = { done = false }
    r.handle = run_argv.run_async_captured(cmd, function(ok_, out_, code_, err_, sig_)
      r.done, r.ok, r.out, r.code, r.err, r.signal = true, ok_, out_, code_, err_, sig_
    end, nil, opts)
    vim.wait(20000, function()
      return r.done
    end, 20)
    return r
  end

  local TEN_KB = child({ "io.stdout:write(string.rep('x', 10000))" })

  -- a tap that raises does not hang the run (the pipe must still close), and the output is still counted;
  -- the error is reported on the main loop: caught here for the duration of the case, so it is asserted and
  -- does not leak as a stray scheduled error (a runner's guard would rightly count it against this spec)
  do
    local real_schedule = vim.schedule
    local reported = {}
    vim.schedule = function(fn)
      return real_schedule(function()
        local okf, e = pcall(fn)
        if not okf then
          reported[#reported + 1] = tostring(e)
        end
      end)
    end
    local okr, r = pcall(run, TEN_KB, {
      on_stdout = function(_, data)
        if data == nil then
          error("tap boom")
        end
      end,
    })
    vim.wait(300, function()
      return #reported > 0
    end, 10)
    vim.schedule = real_schedule
    ok(okr, "a raising tap: the run itself does not raise (" .. tostring(r) .. ")")
    ok(r.done, "a raising tap: on_done still comes")
    eq(r.code, 0, "a raising tap: the run's exit code")
    eq(#(r.out or ""), 10000, "a raising tap: the output is still collected")
    eq(#reported, 1, "a raising tap: the error is reported once, on the main loop")
    ok(reported[1]:find("tap boom", 1, true) ~= nil, "a raising tap: ... with its message")
  end

  -- keep_stdout = false with a cap: nothing is kept, also not the piece that fitted the cap
  do
    local tapped = 0
    local r = run(TEN_KB, {
      max_output_bytes = 7000,
      keep_stdout = false,
      on_stdout = function(_, data)
        tapped = tapped + #(data or "")
      end,
    })
    eq(r.code, run_argv.OUTPUT_LIMIT_CODE, "keep_stdout + cap: stopped at the cap")
    eq(r.out, "", "keep_stdout + cap: nothing is kept")
    eq(tapped, 7000, "keep_stdout + cap: the tap saw exactly what fitted")
  end

  -- with keep_stdout (default) and a cap: what fitted is kept
  do
    local r = run(TEN_KB, { max_output_bytes = 7000, on_stdout = function() end })
    eq(#r.out, 7000, "cap: what fitted is kept")
  end

  -- stop(): the signal is checked, the colon form works, escalate_ms ends a run
  do
    local SLEEP = child({ "vim.wait(60000, function() return false end, 100)" })
    local r = { done = false }
    local h = run_argv.run_async_captured(SLEEP, function()
      r.done = true
    end)
    local bad = pcall(h.stop, "sigkil")
    eq(bad, false, "stop(): a misspelt signal is an error, not a silent no-op")
    eq(h.is_finished(), false, "is_finished(): still running")
    h:stop("sigterm", { escalate_ms = 500 })
    ok(
      vim.wait(20000, function()
        return r.done
      end, 20),
      "stop(): the colon form with escalate_ms ends the run"
    )
    eq(h.is_finished(), true, "is_finished(): ended")
    h.stop() -- after the end: no error, nothing signalled
  end

  -- the tree kill starts taskkill by its absolute path, never a `taskkill.exe` of the current directory
  if vim.fn.has("win32") == 1 then
    local path = run_argv._taskkill():gsub("\\", "/"):lower()
    ok(path:find("/system32/taskkill%.exe$") ~= nil, "taskkill: the System32 one (" .. path .. ")")
  end
end
