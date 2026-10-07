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
