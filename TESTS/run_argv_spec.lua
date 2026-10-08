-- TESTS/run_argv_spec.lua — lib.nvim.cross.run_argv

return function(H)
  local eq, ok = H.eq, H.ok

  local run_argv = require("lib.nvim.cross.run_argv")

  -- ------------------------------------------------------------ run_blocking

  -- A real, trivially-successful command.
  local echo_ok, echo_err = run_argv.run_blocking({ "echo", "hello" })
  eq(echo_ok, true, "run_blocking: a successful command reports ok")
  eq(echo_err, nil, "run_blocking: a successful command has no error")

  -- A real command that exits non-zero.
  local fail_ok, fail_err = run_argv.run_blocking({ "sh", "-c", "exit 3" })
  eq(fail_ok, false, "run_blocking: a non-zero exit reports failure")
  ok(fail_err ~= nil, "run_blocking: a non-zero exit reports an error")

  -- Regression: a command that can't be spawned at all (ENOENT) used to
  -- raise synchronously through vim.system() instead of returning
  -- (false, err) like every other failure path here.
  local enoent_ok, enoent_err = run_argv.run_blocking({ "this-binary-does-not-exist-anywhere" })
  eq(
    enoent_ok,
    false,
    "run_blocking: an unspawnable command reports failure, not an uncaught error"
  )
  ok(enoent_err ~= nil, "run_blocking: an unspawnable command reports an error message")

  -- ------------------------------------------------------- run_blocking_captured

  local cap_ok, cap_out = run_argv.run_blocking_captured({ "echo", "captured text" })
  eq(cap_ok, true, "run_blocking_captured: a successful command reports ok")
  ok(cap_out:find("captured text", 1, true) ~= nil, "run_blocking_captured: stdout is captured")

  local cap_fail_ok, cap_fail_out = run_argv.run_blocking_captured({ "sh", "-c", "exit 1" })
  eq(cap_fail_ok, false, "run_blocking_captured: a non-zero exit reports failure")
  eq(
    type(cap_fail_out),
    "string",
    "run_blocking_captured: output is always a string, even on failure"
  )

  -- Same ENOENT regression as run_blocking: must not raise.
  local cap_enoent_ok, cap_enoent_out =
    run_argv.run_blocking_captured({ "this-binary-does-not-exist-anywhere" })
  eq(
    cap_enoent_ok,
    false,
    "run_blocking_captured: an unspawnable command reports failure, not an uncaught error"
  )
  eq(
    type(cap_enoent_out),
    "string",
    "run_blocking_captured: still returns a string on the ENOENT path"
  )

  -- ------------------------------------------------------- binary (byte-exact)

  -- A child Neovim writes a fixed byte string straight to fd 1 through libuv
  -- (no C-runtime newline translation): CRLF, a NUL, a lone CR, a high byte.
  local script = H.tmpfile(".lua")
  vim.fn.writefile({ 'vim.uv.fs_write(1, "a\\r\\nb\\0c\\r\\n\\r\\255")' }, script)
  local argv = { vim.v.progpath, "--headless", "-u", "NONE", "-l", script }
  local exact = "a\r\nb\0c\r\n\r\255"

  local bin_ok, bin_out = run_argv.run_blocking_captured(argv, nil, { binary = true })
  eq(bin_ok, true, "run_blocking_captured{binary}: the child ran")
  eq(bin_out, exact, "run_blocking_captured{binary}: stdout is delivered byte for byte")

  -- Default mode is text: `\r\n` becomes `\n` (vim.system's own documented
  -- behaviour). Unchanged by the new option -- callers that never pass it must
  -- see exactly what they saw before.
  local text_ok, text_out = run_argv.run_blocking_captured(argv)
  eq(text_ok, true, "run_blocking_captured: default mode still runs the child")
  eq(
    text_out,
    "a\nb\0c\n\r\255",
    "run_blocking_captured: default mode is text (\\r\\n -> \\n), as before"
  )

  local async_done, async_ok, async_out = false, nil, nil
  run_argv.run_async_captured(argv, function(ok_, out_)
    async_done, async_ok, async_out = true, ok_, out_
  end, nil, { binary = true })
  vim.wait(10000, function()
    return async_done
  end, 20)
  ok(async_done, "run_async_captured{binary}: on_done fires")
  eq(async_ok, true, "run_async_captured{binary}: the child ran")
  eq(async_out, exact, "run_async_captured{binary}: stdout is delivered byte for byte")

  local async_text_done, async_text_out = false, nil
  run_argv.run_async_captured(argv, function(_, out_)
    async_text_done, async_text_out = true, out_
  end)
  vim.wait(10000, function()
    return async_text_done
  end, 20)
  eq(async_text_out, "a\nb\0c\n\r\255", "run_async_captured: default mode is text, as before")
  vim.fn.delete(script)

  -- ------------------------------------------- env / cwd / timeout / result

  -- A child Neovim that reports its environment and working directory on
  -- stdout, writes to stderr and exits with a code of its own.
  local probe = H.tmpfile(".lua")
  vim.fn.writefile({
    'io.stdout:write((os.getenv("LIB_SPEC_VAR") or "unset") .. "|" .. vim.uv.cwd())',
    'io.stderr:write("to-stderr")',
    "os.exit(3)",
  }, probe)
  local probe_argv = { vim.v.progpath, "-n", "-i", "NONE", "--headless", "-u", "NONE", "-l", probe }
  local work = vim.fn.tempname() .. "-run-argv-cwd"
  vim.fn.mkdir(work, "p")
  local function same_dir(a, b)
    return vim.fs.normalize(vim.uv.fs_realpath(a) or a)
      == vim.fs.normalize(vim.uv.fs_realpath(b) or b)
  end

  local res = run_argv.run_blocking_result(probe_argv, nil, {
    env = { LIB_SPEC_VAR = "from-opts" },
    cwd = work,
  })
  eq(res.ok, false, "run_blocking_result: a non-zero exit is not ok")
  eq(res.code, 3, "run_blocking_result: ... with the child's exit code")
  eq(res.stderr, "to-stderr", "run_blocking_result: ... and its stderr")
  eq(res.timed_out, false, "run_blocking_result: ... which is not a timeout")
  local seen_var, seen_cwd = res.stdout:match("^(.-)|(.*)$")
  eq(seen_var, "from-opts", "run_blocking_result: opts.env reaches the child")
  ok(
    seen_cwd and same_dir(seen_cwd, work),
    "run_blocking_result: opts.cwd is the child's directory"
  )

  local plain = run_argv.run_blocking_result(probe_argv)
  eq(plain.stdout:match("^(.-)|"), "unset", "run_blocking_result: no env entry unless asked for")

  local good = run_argv.run_blocking_result({ vim.v.progpath, "--version" })
  eq(good.ok, true, "run_blocking_result: a successful command is ok")
  eq(good.code, 0, "run_blocking_result: ... exit code 0")
  ok(good.stdout:find("NVIM", 1, true) ~= nil, "run_blocking_result: ... stdout captured")
  eq(good.stderr, "", 'run_blocking_result: ... an empty stderr is ""')

  local missing = run_argv.run_blocking_result({ "this-binary-does-not-exist-anywhere" })
  eq(missing.ok, false, "run_blocking_result: an unspawnable command is not ok")
  eq(missing.code, -1, "run_blocking_result: ... code -1")
  eq(missing.stdout, "", "run_blocking_result: ... no stdout")
  ok(
    type(missing.stderr) == "string" and missing.stderr ~= "",
    "run_blocking_result: ... the reason in stderr"
  )

  local sleeper = H.tmpfile(".lua")
  vim.fn.writefile({ "vim.wait(60000, function() return false end, 50)" }, sleeper)
  local sleeper_argv =
    { vim.v.progpath, "-n", "-i", "NONE", "--headless", "-u", "NONE", "-l", sleeper }
  local slow = run_argv.run_blocking_result(sleeper_argv, nil, { timeout_ms = 300 })
  eq(slow.timed_out, true, "run_blocking_result: a process past timeout_ms is timed out")
  eq(slow.code, 124, "run_blocking_result: ... with the timeout(1) exit code")
  eq(slow.ok, false, "run_blocking_result: ... and not ok")

  -- A child that catches SIGTERM and exits normally reports no signal; the deadline still
  -- makes it a timeout (this is what a CI runner's nvim does when it is the sleeper).
  if vim.fn.has("win32") == 0 and vim.fn.executable("sh") == 1 then
    local trapped = run_argv.run_blocking_result(
      { "sh", "-c", "trap 'exit 0' TERM; while :; do sleep 0.05; done" },
      nil,
      { timeout_ms = 300 }
    )
    eq(trapped.code, 124, "run_blocking_result: a child that traps SIGTERM: the timeout code")
    eq(trapped.timed_out, true, "run_blocking_result: ... is still timed out")
    local early = run_argv.run_blocking_result(
      { "sh", "-c", "exit 124" },
      nil,
      { timeout_ms = 20000 }
    )
    eq(early.timed_out, false, "run_blocking_result: an early exit 124 of its own is no timeout")
  end

  -- The deadline is our own timer, so a loop that was not iterated for a while before
  -- the call (libuv's cached time is then stale and a timer armed on it fires early)
  -- must not turn a timeout into "not timed out": busy-wait first, then run a child
  -- that handles SIGTERM and exits 0 (what Neovim does).
  do
    local posix = vim.fn.has("win32") == 0 and vim.fn.executable("sh") == 1
    local term_argv = posix and { "sh", "-c", "trap 'exit 0' TERM; while :; do sleep 0.05; done" }
      or sleeper_argv
    local function stall(ms)
      local t = vim.uv.hrtime()
      while (vim.uv.hrtime() - t) / 1e6 < ms do
      end
    end

    stall(230)
    local stalled = run_argv.run_blocking_result(term_argv, nil, { timeout_ms = 300 })
    eq(stalled.timed_out, true, "run_blocking_result: a stalled loop before the call: timed out")
    eq(stalled.code, 124, "run_blocking_result: ... code 124")
    ok(stalled.signal ~= 0, "run_blocking_result: ... with a non-zero signal")

    stall(230)
    local c_ok = run_argv.run_blocking_captured(term_argv, nil, { timeout_ms = 300 })
    eq(c_ok, false, "run_blocking_captured: a stalled loop before the call: a failure")
    stall(230)
    local c_ok2 =
      run_argv.run_blocking_captured(term_argv, nil, { timeout_ms = 300, max_output_bytes = 1000 })
    eq(c_ok2, false, "run_blocking_captured: ... also with an output cap")

    stall(230)
    local s_done, s_res
    run_argv.run_async_captured(term_argv, function(_, _, code_, _, sig_)
      s_done, s_res = true, { code = code_, signal = sig_ }
    end, nil, { timeout_ms = 300 })
    vim.wait(8000, function()
      return s_done
    end, 20)
    ok(s_done, "run_async_captured: a stalled loop before the call: on_done fires")
    eq((s_res or {}).code, 124, "run_async_captured: ... code 124")
    ok(((s_res or {}).signal or 0) ~= 0, "run_async_captured: ... with a non-zero signal")

    if posix then
      -- A child that ignores SIGTERM is killed (SIGKILL) after the grace period.
      local stubborn_argv = { "sh", "-c", "trap '' TERM; while :; do sleep 0.05; done" }
      local stubborn = run_argv.run_blocking_result(stubborn_argv, nil, { timeout_ms = 2000 })
      eq(stubborn.timed_out, true, "run_blocking_result: a child ignoring SIGTERM: timed out")
      eq(stubborn.code, 124, "run_blocking_result: ... code 124")
      eq(stubborn.signal, 9, "run_blocking_result: ... killed with SIGKILL")

      local b_done, b_res
      run_argv.run_async_captured(stubborn_argv, function(_, _, code_, _, sig_)
        b_done, b_res = true, { code = code_, signal = sig_ }
      end, nil, { timeout_ms = 2000 })
      vim.wait(12000, function()
        return b_done
      end, 20)
      ok(b_done, "run_async_captured: a child ignoring SIGTERM: on_done fires")
      eq((b_res or {}).code, 124, "run_async_captured: ... code 124")
      eq((b_res or {}).signal, 9, "run_async_captured: ... signal 9")
    end
  end

  -- the same options on the older runners
  local cap_ok_, cap_out_ = run_argv.run_blocking_captured(probe_argv, nil, {
    env = { LIB_SPEC_VAR = "captured" },
  })
  eq(cap_ok_, false, "run_blocking_captured: the child exits 3")
  eq(cap_out_:match("^(.-)|"), "captured", "run_blocking_captured: opts.env reaches the child")
  local cap_slow_ok = run_argv.run_blocking_captured(sleeper_argv, nil, { timeout_ms = 300 })
  eq(cap_slow_ok, false, "run_blocking_captured: opts.timeout_ms kills a slow process")

  local a_done, a_ok, a_out, a_code, a_err
  run_argv.run_async_captured(probe_argv, function(ok_, out_, code_, err_)
    a_done, a_ok, a_out, a_code, a_err = true, ok_, out_, code_, err_
  end, nil, { env = { LIB_SPEC_VAR = "async" }, cwd = work })
  vim.wait(10000, function()
    return a_done
  end, 20)
  ok(a_done, "run_async_captured: on_done fires")
  eq(a_ok, false, "run_async_captured: the child exits 3")
  eq(a_code, 3, "run_async_captured: ... and the code is reported")
  eq(a_err, "to-stderr", "run_async_captured: ... and the stderr")
  eq(a_out:match("^(.-)|"), "async", "run_async_captured: opts.env reaches the child")
  ok(same_dir(a_out:match("|(.*)$"), work), "run_async_captured: opts.cwd is the child's directory")

  local t_done, t_code
  run_argv.run_async_captured(sleeper_argv, function(_, _, code_)
    t_done, t_code = true, code_
  end, nil, { timeout_ms = 300 })
  vim.wait(10000, function()
    return t_done
  end, 20)
  ok(t_done, "run_async_captured: a timed-out process still reports")
  eq(t_code, 124, "run_async_captured: ... with exit code 124")

  -- A process that merely exits 124 by itself is not a timeout.
  local own_124 = run_argv.run_blocking_result({
    vim.v.progpath,
    "-n",
    "-i",
    "NONE",
    "--headless",
    "-u",
    "NONE",
    "-c",
    "cquit 124",
  })
  eq(own_124.code, 124, "run_blocking_result: an exit code of 124 is reported")
  eq(own_124.timed_out, false, "run_blocking_result: ... but with no timeout_ms it is no timeout")

  -- ... and not with a timeout_ms that was not reached either: only a kill for the
  -- deadline is a timeout.
  local own_124_budget = run_argv.run_blocking_result({
    vim.v.progpath,
    "-n",
    "-i",
    "NONE",
    "--headless",
    "-u",
    "NONE",
    "-c",
    "cquit 124",
  }, nil, { timeout_ms = 60000 })
  eq(own_124_budget.code, 124, "run_blocking_result: the child's own 124 is reported")
  eq(
    own_124_budget.timed_out,
    false,
    "run_blocking_result: ... and is no timeout although timeout_ms is set"
  )

  -- A tiny budget must give a result, not an error from indexing a nil wait().
  for _, ms in ipairs({ 0, 1 }) do
    local r_ok, r = pcall(run_argv.run_blocking_result, sleeper_argv, nil, { timeout_ms = ms })
    eq(r_ok, true, ("run_blocking_result: timeout_ms=%d does not throw"):format(ms))
    eq(r.ok, false, ("run_blocking_result: timeout_ms=%d is a failure"):format(ms))
    local c_ok, c_res =
      pcall(run_argv.run_blocking_captured, sleeper_argv, nil, { timeout_ms = ms })
    eq(c_ok, true, ("run_blocking_captured: timeout_ms=%d does not throw"):format(ms))
    eq(c_res, false, ("run_blocking_captured: timeout_ms=%d is a failure"):format(ms))
  end

  -- ------------------------------------------------------- max_output_bytes

  -- A child that prints ~3 MB. Under a cap it is stopped and the run says why.
  local big = H.tmpfile(".lua")
  vim.fn.writefile({
    "local chunk = string.rep('x', 65536)",
    "for _ = 1, 48 do io.stdout:write(chunk) end",
    "io.stdout:flush()",
  }, big)
  local big_argv = { vim.v.progpath, "-n", "-i", "NONE", "--headless", "-u", "NONE", "-l", big }

  local capped = run_argv.run_blocking_result(big_argv, nil, { max_output_bytes = 100000 })
  eq(capped.ok, false, "run_blocking_result: output past max_output_bytes is a failure")
  eq(capped.code, run_argv.OUTPUT_LIMIT_CODE, "run_blocking_result: ... with the output-limit code")
  ok(#capped.stdout <= 100000, "run_blocking_result: ... and stdout holds at most the cap")
  ok(#capped.stdout > 0, "run_blocking_result: ... and what fitted")
  ok(capped.stderr:find("exceeded", 1, true) ~= nil, "run_blocking_result: ... and stderr says why")
  eq(capped.timed_out, false, "run_blocking_result: ... which is not a timeout")

  local under = run_argv.run_blocking_result(big_argv, nil, { max_output_bytes = 10 * 1024 * 1024 })
  eq(under.ok, true, "run_blocking_result: output under the cap is untouched")
  eq(#under.stdout, 48 * 65536, "run_blocking_result: ... byte for byte")

  local cap_ok2, cap_out2 =
    run_argv.run_blocking_captured(big_argv, nil, { max_output_bytes = 100000 })
  eq(cap_ok2, false, "run_blocking_captured: output past the cap is a failure")
  ok(#cap_out2 <= 100000, "run_blocking_captured: ... and cut at the cap")

  local o_done, o_ok, o_out, o_code, o_err
  run_argv.run_async_captured(big_argv, function(ok_, out_, code_, err_)
    o_done, o_ok, o_out, o_code, o_err = true, ok_, out_, code_, err_
  end, nil, { max_output_bytes = 100000 })
  vim.wait(20000, function()
    return o_done
  end, 20)
  ok(o_done, "run_async_captured: a runaway process still reports")
  eq(o_ok, false, "run_async_captured: ... as a failure")
  eq(o_code, run_argv.OUTPUT_LIMIT_CODE, "run_async_captured: ... with the output-limit code")
  ok(#o_out <= 100000, "run_async_captured: ... stdout cut at the cap")
  ok(o_err:find("exceeded", 1, true) ~= nil, "run_async_captured: ... and the reason in stderr")
  vim.fn.delete(big)

  -- CRLF handling is the same with and without a cap: text mode rewrites it.
  local crlf_argv = {
    vim.v.progpath,
    "-n",
    "-i",
    "NONE",
    "--headless",
    "-u",
    "NONE",
    "-c",
    -- written past the C runtime, which would turn "\n" into "\r\n" on Windows
    "lua vim.uv.fs_write(1, 'a\\r\\nb')",
    "-c",
    "qa!",
  }
  local crlf = run_argv.run_blocking_result(crlf_argv, nil, { max_output_bytes = 1000 })
  ok(
    crlf.stdout:find("\r", 1, true) == nil,
    "run_blocking_result: a capped run still rewrites CRLF in text mode"
  )

  -- ------------------------------------------------- async answer at the deadline

  -- A grandchild that keeps the output pipes open must not delay the answer
  -- past the deadline (POSIX: the sleeper outlives the killed shell).
  if vim.fn.has("win32") == 0 then
    local g_done, g_code
    local started = vim.uv.hrtime()
    run_argv.run_async_captured({ "sh", "-c", "sleep 30 & wait" }, function(_, _, code_)
      g_done, g_code = true, code_
    end, nil, { timeout_ms = 300 })
    vim.wait(8000, function()
      return g_done
    end, 20)
    ok(g_done, "run_async_captured: a timeout is answered although a descendant holds the pipes")
    ok(
      (vim.uv.hrtime() - started) / 1e6 < 6000,
      "run_async_captured: ... at the deadline (plus grace), not when the sleeper ends"
    )
    eq(g_code, 124, "run_async_captured: ... with exit code 124")
  end

  -- A process killed by a signal reports exit status 0 plus `signal`: success
  -- must not be read from the status alone. POSIX only.
  if vim.fn.has("win32") == 0 then
    local killed = run_argv.run_blocking_result({ "sh", "-c", "kill -9 $$" })
    eq(killed.ok, false, "run_blocking_result: a process killed by a signal is not ok")
    eq(killed.signal, 9, "run_blocking_result: ... the signal is reported")
    eq(killed.code, 137, "run_blocking_result: ... as 128 + signal, the shell's convention")
    eq(killed.timed_out, false, "run_blocking_result: ... which is not a timeout")

    local k_done, k_ok, k_code, k_signal
    run_argv.run_async_captured({ "sh", "-c", "kill -9 $$" }, function(ok_, _, code_, _, signal_)
      k_done, k_ok, k_code, k_signal = true, ok_, code_, signal_
    end)
    vim.wait(10000, function()
      return k_done
    end, 20)
    ok(k_done, "run_async_captured: a killed process reports")
    eq(k_signal, 9, "run_async_captured: the terminating signal is the 5th argument")
    -- `ok`/`code` keep reading the exit status alone, as they always did.
    eq(k_ok, true, "run_async_captured: ok is still the bare exit status (compatible)")
    eq(k_code, 0, "run_async_captured: ... and so is code")
  end

  vim.fn.delete(probe)
  vim.fn.delete(sleeper)
  vim.fn.delete(work, "rf")
end
