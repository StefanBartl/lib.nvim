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
end
