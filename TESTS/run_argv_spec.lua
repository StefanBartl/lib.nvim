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
end
