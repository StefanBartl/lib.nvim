-- docs/TESTS/system_job_spec.lua — lib.nvim.system.job
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
    local opts = { command = "sh", args = { "-c", script } }
    opts[key] = function(_, line)
      lines[#lines + 1] = line
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
end
