-- TESTS/system_job_spec.lua — lib.nvim.system.job
--
-- The child is a headless Neovim running a small Lua script rather than
-- `sh -c printf`: no shell, so the spec runs on Windows without `sh` in PATH
-- too, and the exact byte stream (specifically whether it ends in a newline)
-- is still stated in the test instead of depending on a file on disk.

return function(H)
  local eq, ok = H.eq, H.ok

  local job = require("lib.nvim.system.job")

  local nvim = vim.v.progpath

  -- `vim.uv.fs_write`, not `io.stdout:write`: the C runtime's stdout is in text mode on
  -- Windows and turns every "\n" into "\r\n", so the bytes the test states would not be
  -- the bytes the job sees.
  local PRELUDE = table.concat({
    "local function out(s) vim.uv.fs_write(1, s) end",
    "local function err(s) vim.uv.fs_write(2, s) end",
    "",
  }, "\n")

  ---A job spec running `body` (after PRELUDE) in a headless Neovim.
  ---@param body string
  ---@param extra? table additional Lib.System.Job.Opts fields
  ---@return Lib.System.Job.Opts
  local function lua(body, extra)
    local path = vim.fn.tempname() .. ".lua"
    local f = assert(io.open(path, "wb"))
    f:write(PRELUDE, body, "\n")
    f:close()
    local spec = vim.tbl_extend("force", extra or {}, {
      command = nvim,
      args = { "-n", "-i", "NONE", "-u", "NONE", "--headless", "-l", path },
    })
    return spec
  end

  ---A job spec writing exactly `s` to stdout.
  ---@param s string
  ---@return Lib.System.Job.Opts
  local function emit(s)
    return lua(("out(%q)"):format(s))
  end

  ---A job spec exiting with `code` and no output.
  ---@param code integer
  ---@return Lib.System.Job.Opts
  local function exit_with(code)
    return lua(("os.exit(%d)"):format(code))
  end

  ---A job spec copying stdin to stdout byte for byte (a portable `cat`).
  ---@param extra? table additional Lib.System.Job.Opts fields
  ---@return Lib.System.Job.Opts
  local function cat(extra)
    return lua(
      table.concat({
        "local chunks = {}",
        "while true do",
        "  local data = assert(vim.uv.fs_read(0, 65536))",
        "  if data == '' then break end",
        "  chunks[#chunks + 1] = data",
        "end",
        "out(table.concat(chunks))",
      }, "\n"),
      extra
    )
  end

  ---Run `spec` and collect the callback lines.
  ---@param spec Lib.System.Job.Opts
  ---@param key "on_stdout"|"on_stderr"
  ---@return string[]
  local function collect(spec, key)
    local lines = {}
    ---@type Lib.System.Job.Opts
    local opts = vim.deepcopy(spec)
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
  local a = collect(emit("one\ntwo\n"), "on_stdout")
  eq(#a, 2, "stdout: one callback per newline-terminated line")
  eq(a[1], "one", "stdout: first line")
  eq(a[2], "two", "stdout: second line")

  -- Regression: output that does NOT end with a newline. The trailing
  -- fragment is still a line; without an EOF flush it was silently dropped,
  -- so the last line of a file lacking a terminator simply vanished.
  local b = collect(emit("one\ntwo"), "on_stdout")
  eq(#b, 2, "stdout: a final line with no trailing newline is still delivered")
  eq(b[2], "two", "stdout: and it carries the right text")

  -- A single unterminated line, i.e. the whole output is the fragment.
  local c = collect(emit("only"), "on_stdout")
  eq(#c, 1, "stdout: output that is one unterminated line delivers one line")
  eq(c[1], "only", "stdout: with its text intact")

  -- CRLF: the \r belongs to the terminator, not to the line's content.
  local d = collect(emit("a\r\nb\r\n"), "on_stdout")
  eq(d[1], "a", "stdout: a trailing \\r is stripped from a CRLF line")
  eq(d[2], "b", "stdout: on every line, not just the first")

  -- stderr runs through the same buffering.
  local e = collect(lua('err("oops\\n")'), "on_stderr")
  eq(#e, 1, "stderr: is line-buffered too")
  eq(e[1], "oops", "stderr: with the right text")

  -- No output at all must not invent an empty line.
  local f = collect(lua(""), "on_stdout")
  eq(#f, 0, "stdout: a command with no output produces no callbacks")

  -- Callbacks are optional: omitting them must not raise.
  local handle = job.start(emit("x\n"))
  ok(handle ~= nil, "start(): returns a handle with no callbacks given")
  handle:wait()

  -- args defaults to {}. Needs a program that exits on its own without any
  -- argument: `whoami` exists on Windows, Linux and macOS, `true` not on Windows.
  local bare = job.start({ command = "whoami" })
  ok(bare ~= nil, "start(): args is optional")
  bare:wait()

  -- ---------------------------------------------------------- start_blocking

  -- Full output available immediately on return -- no extra vim.wait needed,
  -- unlike start()+wait() above, which is exactly the point of this tier.
  local blocking_obj = job.start_blocking(emit("one\ntwo\n"))
  eq(blocking_obj.code, 0, "start_blocking: exit code captured")
  eq(
    blocking_obj.stdout,
    "one\ntwo\n",
    "start_blocking: full stdout captured, no line-callback wait needed"
  )

  local blocking_fail = job.start_blocking(exit_with(3))
  eq(blocking_fail.code, 3, "start_blocking: non-zero exit code captured")

  local blocking_stdin = job.start_blocking(cat({ stdin = "piped in\n" }))
  eq(blocking_stdin.stdout, "piped in\n", "start_blocking: opts.stdin reaches the process")

  -- ------------------------------------------------------------------ chain

  -- Success path: three steps, all exit 0.
  do
    local done, chain_ok, results
    job.chain({
      emit("a"),
      emit("b"),
      emit("c"),
    }, function(cb_ok, cb_results)
      chain_ok, results, done = cb_ok, cb_results, true
    end)
    vim.wait(30000, function()
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
      emit("a"),
      exit_with(1),
      emit("never"),
    }, function(cb_ok, cb_results)
      chain_ok, results, done = cb_ok, cb_results, true
    end)
    vim.wait(30000, function()
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
      emit("hello"),
      cat(),
    }, function(_, cb_results)
      results, done = cb_results, true
    end)
    vim.wait(30000, function()
      return done == true
    end, 10)

    ok(done, "chain: stdin-piping example finishes")
    eq(results[2].stdout, "hello", "chain: second step received the first step's stdout as stdin")
  end

  -- An explicit opts.stdin on a step overrides the auto-piped default.
  do
    local done, results
    job.chain({
      emit("ignored"),
      cat({ stdin = "explicit\n" }),
    }, function(_, cb_results)
      results, done = cb_results, true
    end)
    vim.wait(30000, function()
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
