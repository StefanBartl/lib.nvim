-- TESTS/system_job_spec.lua — lib.nvim.system.job
--
-- Uses `sh -c printf` rather than a fixture file so the exact byte stream —
-- specifically whether it ends in a newline — is stated in the test instead
-- of depending on what some file on disk happens to end with.

return function(H)
  local eq, ok = H.eq, H.ok

  local job = require("lib.nvim.system.job")

  ---Run `script` under `sh -c` and collect the callback lines.
  ---@param script string
  ---@param key "on_stdout"|"on_stderr"
  ---@return string[]
  local function collect(script, key)
    local lines = {}
    ---@type Lib.System.Job.Opts
    local opts = { command = "sh", args = { "-c", script } }
    -- Named rather than indexed by `key`: a computed key makes the target
    -- every field of the class at once.
    local function record(_, line)
      lines[#lines + 1] = line
    end
    if key == "on_stdout" then
      opts.on_stdout = record
    else
      opts.on_stderr = record
    end
    local handle = job.start(opts)
    handle:wait()
    -- Callbacks are vim.schedule-wrapped, so the process exiting is not the
    -- same event as the last line arriving.
    vim.wait(500, function()
      return false
    end, 20)
    return lines
  end

  -- Output that ends with a newline: one callback per line, no empty tail.
  local a = collect("printf 'one\\ntwo\\n'", "on_stdout")
  eq(#a, 2, "stdout: one callback per newline-terminated line")
  eq(a[1], "one", "stdout: first line")
  eq(a[2], "two", "stdout: second line")

  -- Regression: output that does NOT end with a newline. The trailing
  -- fragment is still a line; without an EOF flush it was silently dropped,
  -- so the last line of a file lacking a terminator simply vanished.
  local b = collect("printf 'one\\ntwo'", "on_stdout")
  eq(#b, 2, "stdout: a final line with no trailing newline is still delivered")
  eq(b[2], "two", "stdout: and it carries the right text")

  -- A single unterminated line, i.e. the whole output is the fragment.
  local c = collect("printf 'only'", "on_stdout")
  eq(#c, 1, "stdout: output that is one unterminated line delivers one line")
  eq(c[1], "only", "stdout: with its text intact")

  -- CRLF: the \r belongs to the terminator, not to the line's content.
  local d = collect("printf 'a\\r\\nb\\r\\n'", "on_stdout")
  eq(d[1], "a", "stdout: a trailing \\r is stripped from a CRLF line")
  eq(d[2], "b", "stdout: on every line, not just the first")

  -- stderr runs through the same buffering.
  local e = collect("printf 'oops\\n' 1>&2", "on_stderr")
  eq(#e, 1, "stderr: is line-buffered too")
  eq(e[1], "oops", "stderr: with the right text")

  -- No output at all must not invent an empty line.
  local f = collect("true", "on_stdout")
  eq(#f, 0, "stdout: a command with no output produces no callbacks")

  -- Callbacks are optional: omitting them must not raise.
  local handle = job.start({ command = "sh", args = { "-c", "printf 'x\\n'" } })
  ok(handle ~= nil, "start(): returns a handle with no callbacks given")
  handle:wait()

  -- args defaults to {}.
  local bare = job.start({ command = "true" })
  ok(bare ~= nil, "start(): args is optional")
  bare:wait()

  -- ---------------------------------------------------------- start_blocking

  -- Full output available immediately on return -- no extra vim.wait needed,
  -- unlike start()+wait() above, which is exactly the point of this tier.
  local blocking_obj = job.start_blocking({
    command = "sh",
    args = { "-c", "printf 'one\\ntwo\\n'" },
  })
  eq(blocking_obj.code, 0, "start_blocking: exit code captured")
  eq(
    blocking_obj.stdout,
    "one\ntwo\n",
    "start_blocking: full stdout captured, no line-callback wait needed"
  )

  local blocking_fail = job.start_blocking({ command = "sh", args = { "-c", "exit 3" } })
  eq(blocking_fail.code, 3, "start_blocking: non-zero exit code captured")

  local blocking_stdin = job.start_blocking({ command = "cat", stdin = "piped in\n" })
  eq(blocking_stdin.stdout, "piped in\n", "start_blocking: opts.stdin reaches the process")

  -- ------------------------------------------------------------------ chain

  -- Success path: three steps, all exit 0.
  do
    local done, chain_ok, results
    job.chain({
      { command = "sh", args = { "-c", "printf 'a'" } },
      { command = "sh", args = { "-c", "printf 'b'" } },
      { command = "sh", args = { "-c", "printf 'c'" } },
    }, function(cb_ok, cb_results)
      chain_ok, results, done = cb_ok, cb_results, true
    end)
    vim.wait(2000, function()
      return done == true
    end, 10)

    ok(done, "chain: on_done fires")
    ok(chain_ok, "chain: reports ok when every step exits 0")
    eq(#results, 3, "chain: one result per step")
    eq(results[3].stdout, "c", "chain: each step's own stdout is captured")
  end

  -- Failure gating: a failing middle step stops the chain -- no third step.
  do
    local done, chain_ok, results
    job.chain({
      { command = "sh", args = { "-c", "printf 'a'" } },
      { command = "sh", args = { "-c", "exit 1" } },
      { command = "sh", args = { "-c", "printf 'never'" } },
    }, function(cb_ok, cb_results)
      chain_ok, results, done = cb_ok, cb_results, true
    end)
    vim.wait(2000, function()
      return done == true
    end, 10)

    ok(done, "chain: on_done fires even on failure")
    ok(not chain_ok, "chain: reports not-ok when a step fails")
    eq(#results, 2, "chain: stops at the failing step, no third result")
  end

  -- Stdin-piping: each step's stdin defaults to the previous step's stdout.
  do
    local done, results
    job.chain({
      { command = "sh", args = { "-c", "printf 'hello'" } },
      { command = "cat" },
    }, function(_, cb_results)
      results, done = cb_results, true
    end)
    vim.wait(2000, function()
      return done == true
    end, 10)

    ok(done, "chain: stdin-piping example finishes")
    eq(results[2].stdout, "hello", "chain: second step received the first step's stdout as stdin")
  end

  -- An explicit opts.stdin on a step overrides the auto-piped default.
  do
    local done, results
    job.chain({
      { command = "sh", args = { "-c", "printf 'ignored'" } },
      { command = "cat", stdin = "explicit\n" },
    }, function(_, cb_results)
      results, done = cb_results, true
    end)
    vim.wait(2000, function()
      return done == true
    end, 10)

    ok(done, "chain: explicit-stdin example finishes")
    eq(
      results[2].stdout,
      "explicit\n",
      "chain: explicit opts.stdin wins over the auto-piped default"
    )
  end
end
