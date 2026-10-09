---@module 'lib.nvim.cross.run_argv'
--- Low-level argv-based process runner with stdin support.

local M = {}

local uv = vim.uv or vim.loop

-- Decided once: `kill_tree` runs in libuv callbacks (the deadline timer, the
-- stdout handler), where `vim.fn.*` is not allowed.
local IS_WIN = (uv.os_uname().sysname or ""):find("Windows", 1, true) ~= nil

--- Exit code of a run that was stopped for printing more than
--- `opts.max_output_bytes`.
M.OUTPUT_LIMIT_CODE = 125

--- Most stderr text handed back (bytes). A hostile process can print megabytes to
--- stderr; the text ends up in failure messages.
local MAX_STDERR = 64 * 1024

--- Milliseconds the async runner waits after `timeout_ms` for the process to be
--- reaped before it reports the timeout itself.
local GRACE_MS = 1500

--- Options of the `*_captured` and `*_result` runners.
---@class Lib.RunArgv.Opts
---@field binary? boolean Deliver stdout byte for byte (`vim.system` `text = false`): no `\r\n` -> `\n` rewriting, `NUL` and non-UTF-8 bytes intact. Needs Neovim 0.10+ (`vim.system`); the legacy fallback ignores it.
---@field timeout_ms? integer Kill the process (SIGTERM) after this many milliseconds; the run then ends with exit code `124`, the `timeout(1)` convention, whatever the child made of the signal (a child that handles SIGTERM and exits 0, as Neovim does, is a timeout all the same). The deadline is a timer of our own, started once the process is spawned; a child that ignores SIGTERM is killed (SIGKILL) `1500` ms later. On Windows the whole process tree is killed (`taskkill /T`); elsewhere only the direct child is, so a grandchild that keeps the output pipes open can delay their closing -- the async runner settles at the deadline (plus a short grace) anyway, the blocking runner returns once `wait()` gives up. Needs `vim.system`; the legacy fallback ignores it.
---@field max_output_bytes? integer Stop the process once its stdout exceeds this many bytes: the run then ends with exit code `125` (`M.OUTPUT_LIMIT_CODE`), `stdout` holds what fitted and `stderr` says why. A process whose output is the data (`git log` of a repository somebody else wrote) can print gigabytes from a tiny input; without a cap all of it is collected in memory. Needs `vim.system`; the legacy fallback ignores it.
---@field env? table<string, string> Extra environment variables, merged over the inherited environment (an unset name stays inherited). Needs `vim.system`; the legacy fallback ignores it.
---@field cwd? string Working directory of the child. Needs `vim.system`; the legacy fallback ignores it.

--- The result of `run_blocking_result`.
---@class Lib.RunArgv.Result
---@field ok boolean `code == 0`. A process that was killed by a signal is **not** ok.
---@field code integer Exit code: `124` after `opts.timeout_ms`, `125` after `opts.max_output_bytes`, `128 + signal` when a signal killed the process (the shell convention; the OS reports exit status 0 for it), `-1` when `cmd[1]` could not be spawned at all
---@field signal integer The signal that terminated the process, `0` if none (always `0` on the legacy fallback)
---@field stdout string
---@field stderr string|nil Captured stderr (`""` when empty); `nil` only on the legacy fallback, which cannot separate the streams. For a spawn failure it holds the reason.
---@field timed_out boolean The run hit `opts.timeout_ms`: the process was killed for it (`code == 124` and a non-zero `signal`: 15, or 9 when SIGTERM was ignored). A process that merely exits 124 by itself is not a timeout.

---@internal
--- Best effort: kill a process AND its children. `vim.system`'s own timeout and
--- `stop()` signal only the direct child; on Windows the `git.exe` of `cmd\` is a
--- thin wrapper whose real git keeps running (and keeps the pipes open).
--- `taskkill /T` finds the descendants through the PARENT, so the parent must still
--- be alive when it runs: the signal to the direct child is sent only after
--- `taskkill` has finished (and straight away when it cannot be started, or off
--- Windows).
---@param job table|nil  The `vim.system` object.
---@param signal string
local function kill_job(job, signal)
  -- An exited process: its pid may already belong to somebody else (`/F` would
  -- kill that), and `/T` finds descendants only through a live parent anyway.
  if not job or (job.is_closing and job:is_closing()) then
    return
  end
  if IS_WIN and job.pid then
    local started = pcall(
      vim.system,
      { "taskkill", "/PID", tostring(job.pid), "/T", "/F" },
      { text = true },
      function()
        pcall(job.kill, job, signal)
      end
    )
    if started then
      return
    end
  end
  pcall(job.kill, job, signal)
end

---@internal
--- Best effort, no signal afterwards: for a run that already gave up waiting.
---@param job table|nil  The `vim.system` object.
local function kill_tree(job)
  if not job or not job.pid or not IS_WIN or (job.is_closing and job:is_closing()) then
    return
  end
  pcall(
    vim.system,
    { "taskkill", "/PID", tostring(job.pid), "/T", "/F" },
    { text = true },
    function() end
  )
end

---@internal
--- Collect stdout ourselves when a cap is set, so that a runaway process is
--- stopped instead of being read to the end.
---@param opts Lib.RunArgv.Opts|nil
---@param kill fun()
---@return table|nil sink
local function new_sink(opts, kill)
  local cap = opts and opts.max_output_bytes
  if type(cap) ~= "number" or cap ~= cap or cap < 0 then
    return nil
  end
  local sink = { chunks = {}, size = 0, over = false, cap = cap }
  sink.handler = function(_, data)
    if not data or sink.over then
      return
    end
    local room = cap - sink.size
    if #data > room then
      sink.over = true
      if room > 0 then
        sink.chunks[#sink.chunks + 1] = data:sub(1, room)
      end
      sink.size = cap
      kill()
    else
      sink.chunks[#sink.chunks + 1] = data
      sink.size = sink.size + #data
    end
  end
  return sink
end

---@internal
--- `text` without a multi-byte character a byte cap cut in two at its end.
---@param text string
---@return string
local function drop_partial_utf8(text)
  local n, i = #text, #text
  while i > 0 and n - i < 3 and text:byte(i) >= 0x80 and text:byte(i) < 0xC0 do
    i = i - 1
  end
  local lead = i > 0 and text:byte(i) or 0
  local need = lead >= 0xF0 and 4 or lead >= 0xE0 and 3 or lead >= 0xC0 and 2 or 1
  if need > 1 and n - i + 1 < need then
    return text:sub(1, i - 1)
  end
  return text
end

---@internal
---@param sink table
---@param opts Lib.RunArgv.Opts|nil
---@return string
local function sink_stdout(sink, opts)
  local out = table.concat(sink.chunks)
  if not (opts and opts.binary) then
    -- `vim.system` does this for the output it collects itself; with a stream
    -- handler it is ours to do.
    out = out:gsub("\r\n", "\n")
    if sink.over then
      out = drop_partial_utf8(out)
    end
  end
  return out
end

---@internal
--- Collect stderr ourselves, up to `MAX_STDERR` bytes: `vim.system` would
--- otherwise hold ALL of it in memory before `bound_stderr` could cut the text,
--- and a hostile process can print gigabytes there. The rest is read and thrown
--- away (no kill: stderr is not what the caller asked for).
---@return table errs
local function new_errsink()
  local errs = { chunks = {}, size = 0, over = false }
  errs.handler = function(_, data)
    if not data or errs.over then
      return
    end
    local room = MAX_STDERR - errs.size
    if #data > room then
      errs.over = true
      if room > 0 then
        errs.chunks[#errs.chunks + 1] = data:sub(1, room)
      end
      errs.size = MAX_STDERR
    else
      errs.chunks[#errs.chunks + 1] = data
      errs.size = errs.size + #data
    end
  end
  return errs
end

---@internal
---@param errs table
---@param opts Lib.RunArgv.Opts|nil
---@return string
local function err_text(errs, opts)
  local text = table.concat(errs.chunks)
  if not (opts and opts.binary) then
    text = text:gsub("\r\n", "\n")
  end
  if errs.over then
    return drop_partial_utf8(text) .. "..."
  end
  return text
end

---@internal
---@param sink table
---@return string
local function over_message(sink)
  return ("output exceeded %d bytes; the process was stopped"):format(sink.cap)
end

---@internal
--- The deadline of a run: a timer WE own, so "timed out" is a fact we set, not
--- something inferred. `vim.system`'s own `timeout` cannot be used for that: it
--- reports exit code 124 only if the child then exits with 0 or 1, and `signal` is
--- 0 for a child that handles SIGTERM (Neovim does). Inferring it from the clock is
--- no better: libuv timers run on a cached loop time and fire early by however
--- long the loop was not iterated (`uv.update_time()` first narrows that, it does
--- not close it).
---@class Lib.RunArgv.Deadline
---@field fired boolean SIGTERM was sent because the deadline passed.
---@field timer uv.uv_timer_t|nil

---@param get_job fun(): table|nil
---@param opts Lib.RunArgv.Opts|nil
---@param on_fired fun()|nil Runs (in the libuv callback) after the SIGTERM.
---@return Lib.RunArgv.Deadline|nil
local function start_deadline(get_job, opts, on_fired)
  local ms = opts and opts.timeout_ms
  if type(ms) ~= "number" or ms ~= ms or ms < 0 then
    return nil
  end
  local d = { fired = false, timer = uv.new_timer() }
  uv.update_time()
  d.timer:start(ms, 0, function()
    local job = get_job()
    if not job then
      return
    end
    d.fired = true
    kill_job(job, "sigterm")
    if on_fired then
      on_fired()
    end
  end)
  return d
end

---@param d Lib.RunArgv.Deadline|nil
local function stop_deadline(d)
  if d and d.timer then
    pcall(d.timer.stop, d.timer)
    pcall(d.timer.close, d.timer)
    d.timer = nil
  end
end

---@internal
--- Translate our options into `vim.system` options. One place, so the
--- blocking and the async runner cannot drift apart.
---@param input string|nil
---@param opts Lib.RunArgv.Opts|nil
---@param sink table|nil
---@param errs table|nil
---@return table
local function system_opts(input, opts, sink, errs)
  opts = opts or {}
  return {
    text = not opts.binary,
    stdin = input,
    env = opts.env,
    cwd = opts.cwd,
    stdout = sink and sink.handler or nil,
    stderr = errs and errs.handler or nil,
  }
end

---@param cmd string[]
---@param input? string
---@return boolean, string|nil
function M.run_blocking(cmd, input)
  -- vim.system path (Neovim ≥0.10)
  if vim.system then
    -- vim.system raises synchronously when cmd[1] can't be spawned at all
    -- (e.g. ENOENT) rather than yielding a failed SystemCompleted -- guard
    -- it so that case returns (false, err) like every other failure here,
    -- instead of an uncaught error escaping to the caller.
    local ok, res = pcall(function()
      return vim.system(cmd, { text = true, stdin = input }):wait()
    end)
    if not ok then
      return false, tostring(res)
    end
    if res.code == 0 then
      return true, nil
    end
    local detail = res.stderr or ""
    if #detail > MAX_STDERR then
      detail = drop_partial_utf8(detail:sub(1, MAX_STDERR)) .. "..."
    end
    return false, (detail ~= "" and detail) or ("exit code " .. res.code)
  end

  -- Legacy fallback
  local out = vim.fn.system(cmd, input or "")
  if vim.v.shell_error == 0 then
    return true, nil
  end
  return false, out
end

--- Like `run_blocking`, but also returns captured stdout on success — the
--- gap `run_blocking` deliberately leaves open (it was designed for
--- "run this and tell me if it worked", not "run this and give me its
--- output"). Mirrors the legacy `local out = vim.fn.system(cmd)` +
--- `vim.v.shell_error` idiom, just via `vim.system` (no shell) when available.
---
--- By default stdout is handled as **text**: `vim.system` then replaces every
--- `\r\n` with `\n`. That is what a caller wants from a command's messages, and
--- wrong for a command whose output *is the data* (`git show` of a CRLF or
--- binary blob): pass `{ binary = true }` to get the bytes exactly as written.
---@param cmd string[]
---@param input? string
---@param opts? Lib.RunArgv.Opts
---@return boolean ok
---@return string output Captured stdout, both on success and failure
function M.run_blocking_captured(cmd, input, opts)
  if vim.system then
    local job, deadline
    local sink = new_sink(opts, function()
      if job then
        kill_job(job, "sigkill")
      end
    end)
    local errs = new_errsink() -- stderr is not returned here, only kept out of memory
    local ok, res = pcall(function()
      job = vim.system(cmd, system_opts(input, opts, sink, errs))
      deadline = start_deadline(function()
        return job
      end, opts)
      return job:wait(deadline and (opts.timeout_ms + GRACE_MS) or nil)
    end)
    local timed_out = deadline ~= nil and deadline.fired
    stop_deadline(deadline)
    if not ok then
      return false, tostring(res)
    end
    if res == nil then
      -- `wait()` gives up with nil when the process (or a descendant) still
      -- holds the pipes after the kill: report a failure, do not index it.
      kill_tree(job)
      return false, sink and sink_stdout(sink, opts) or ""
    end
    if sink then
      return res.code == 0 and not sink.over and not timed_out, sink_stdout(sink, opts)
    end
    return res.code == 0 and not timed_out, res.stdout or ""
  end

  -- Legacy fallback (Neovim < 0.10): no byte-exact mode exists here, so
  -- `opts.binary` cannot be honoured.
  local out = vim.fn.system(cmd, input or "")
  return vim.v.shell_error == 0, out
end

--- Like `run_blocking_captured`, but reports **everything** the process did as
--- one table: exit code, both streams and whether it ran into
--- `opts.timeout_ms`. `run_blocking_captured` folds all of that into a bare
--- `ok, stdout`, which is enough to ask "what did it print" and not enough to
--- tell a failure's reason (stderr), a timeout (`124`) and a spawn failure
--- (`-1`) apart -- the three things a caller reporting an error to the user
--- needs.
---
--- Blocks the caller like `run_blocking_captured` does; for anything that can
--- take longer than a few milliseconds use `run_async_captured`, which carries
--- the same options and reports the same four values.
---@param cmd string[]
---@param input? string
---@param opts? Lib.RunArgv.Opts
---@return Lib.RunArgv.Result
function M.run_blocking_result(cmd, input, opts)
  if not vim.system then
    -- Legacy fallback: no separate stderr, no timeout/env/cwd.
    local out = vim.fn.system(cmd, input or "")
    local code = vim.v.shell_error
    return { ok = code == 0, code = code, signal = 0, stdout = out, stderr = nil, timed_out = false }
  end

  local job, deadline
  local sink = new_sink(opts, function()
    if job then
      kill_job(job, "sigkill")
    end
  end)
  -- vim.system raises synchronously when cmd[1] cannot be spawned at all
  -- (e.g. ENOENT): the same guard as in the other runners, reported as a
  -- failed result instead of an error escaping to the caller.
  local errs = new_errsink()
  local ok, res = pcall(function()
    job = vim.system(cmd, system_opts(input, opts, sink, errs))
    deadline = start_deadline(function()
      return job
    end, opts)
    -- `wait(ms)` that runs out sends SIGKILL: the escalation for a child that ignores SIGTERM.
    return job:wait(deadline and (opts.timeout_ms + GRACE_MS) or nil)
  end)
  stop_deadline(deadline)
  if not ok then
    return {
      ok = false,
      code = -1,
      signal = 0,
      stdout = "",
      stderr = tostring(res),
      timed_out = false,
    }
  end

  local has_timeout = opts ~= nil and opts.timeout_ms ~= nil
  if res == nil then
    -- `wait()` returns nil when the process (or a descendant: the real git
    -- behind the Windows `cmd\git.exe` wrapper) still holds the pipes after the
    -- kill. There is no result to index; say what happened.
    kill_tree(job)
    return {
      ok = false,
      code = 124,
      signal = 9,
      stdout = sink and sink_stdout(sink, opts) or "",
      stderr = "timed out; the process tree still holds its output pipes",
      timed_out = has_timeout,
    }
  end

  -- A process killed by a signal (the OOM killer, a crash) reports exit status
  -- 0 with `signal` set: counting that as success would hand the caller an
  -- empty or cut-short output as a valid answer. 128 + signal is the shell's
  -- convention for it. A timeout already has a non-zero code (124).
  local code, signal = res.code, res.signal or 0
  local timed_out = deadline ~= nil and deadline.fired
  if timed_out then
    -- the deadline decides, whatever the child made of the SIGTERM
    code, signal = 124, (signal ~= 0 and signal or 15)
  end
  if code == 0 and signal ~= 0 then
    code = 128 + signal
  end
  local stdout, stderr = res.stdout or "", err_text(errs, opts)
  if sink then
    stdout = sink_stdout(sink, opts)
    if sink.over then
      code = M.OUTPUT_LIMIT_CODE
      stderr = over_message(sink)
    end
  end
  return {
    ok = code == 0,
    code = code,
    signal = signal,
    stdout = stdout,
    stderr = stderr,
    -- a process that merely exits 124 by itself is not one
    timed_out = timed_out and not (sink and sink.over),
  }
end

--- Asynchronous counterpart to `run_blocking_captured`: spawns `cmd` and hands
--- the outcome to `on_done` instead of blocking the UI thread until the process
--- exits.
---
--- This exists because `run_blocking`/`run_blocking_captured` are, by a wide
--- margin, the biggest source of UI freezes across the plugins built on this
--- library: they are thin wrappers around `vim.system():wait()` (or
--- `vim.fn.system`), so a caller cannot tell from the call site that the editor
--- stops for the duration. Anything that can take longer than a few
--- milliseconds -- container CLIs, PowerShell, git over the network, image
--- tooling -- belongs here rather than there.
---
--- `on_done` is always invoked on the main loop (`vim.schedule`), so it is safe
--- to touch buffers, windows and `vim.fn.*` from it, and it is invoked **once**.
--- Both stdout and the exit code are passed on; `code` lets a caller report a
--- bare "exit code N" when the process failed without writing anything.
---
--- With `opts.timeout_ms` the answer comes at the deadline (plus a short grace)
--- even when a descendant of the process keeps the pipes open: the process (on
--- Windows its tree) is killed and `on_done` gets code `124`, signal `9`.
---
--- The returned handle has a `stop()` method that sends SIGTERM (on Windows it
--- also kills the process tree). It is a no-op on the legacy fallback path
--- (Neovim < 0.10), where there is no job to kill.
---
--- Text vs. bytes: see `run_blocking_captured` -- `opts.binary` delivers stdout
--- exactly as the process wrote it.
---
--- `stderr` (the 4th `on_done` argument) is captured unconditionally, on
--- success as well as failure -- unlike `run_blocking`'s error string, which
--- only ever exists on failure. A caller distinguishing "nothing to do" from
--- "did something" on a *successful* exit (git writes `push`/`fetch`'s ref
--- updates to stderr, `pull`'s "Already up to date." to stdout) needs both
--- streams from the same successful run, not just the failure-only one.
--- Existing callers that destructure only `(ok, output)` are unaffected --
--- Lua ignores the extra return values. On the legacy fallback (Neovim <
--- 0.10) `stderr` is always `nil`, never `""`: `vim.fn.system` cannot
--- separate the two streams at all, and a caller that treats stderr
--- content as a signal needs to tell "this platform genuinely doesn't know"
--- apart from "known and empty" rather than get a confident wrong answer.
---@param cmd string[]
---@param on_done fun(ok: boolean, output: string, code: integer, stderr: string|nil, signal: integer|nil) `signal` (5th) is the terminating signal, `0` if none, `nil` on the legacy fallback. `ok` is the exit code alone, as it always was -- a process killed by a signal still reads `ok = true`, `code = 0`; a caller that must tell checks `signal`.
---@param input? string
---@param opts? Lib.RunArgv.Opts
---@return { stop: fun() } handle
function M.run_async_captured(cmd, on_done, input, opts)
  if not vim.system then
    -- Legacy fallback: no async process API, and no separate stderr stream
    -- either (`vim.fn.system` only ever returns stdout) -- reported as
    -- `nil`, not `""`, so a caller that treats stderr content as a signal
    -- (e.g. "did this fetch move a ref") can tell "unknown, this platform
    -- can't say" apart from "known and genuinely empty" instead of a
    -- confident-looking wrong answer either way.
    local out = vim.fn.system(cmd, input or "")
    local code = vim.v.shell_error
    vim.schedule(function()
      on_done(code == 0, out, code, nil)
    end)
    return { stop = function() end }
  end

  local job, deadline
  local finished = false
  local sink = new_sink(opts, function()
    if job then
      kill_job(job, "sigkill")
    end
  end)

  -- Deliver the outcome exactly once, whichever of the exit callback and the
  -- deadline timer gets there first.
  local function settle(ok, output, code, stderr, signal)
    if finished then
      return
    end
    finished = true
    stop_deadline(deadline)
    vim.schedule(function()
      on_done(ok, output, code, stderr, signal)
    end)
  end

  -- vim.system raises synchronously when cmd[1] cannot be spawned at all
  -- (e.g. ENOENT) rather than delivering a failed SystemCompleted -- guard it
  -- so that case reaches on_done like every other failure, instead of an
  -- uncaught error escaping into the caller's stack.
  local errs = new_errsink()
  local ok_spawn, spawned = pcall(
    vim.system,
    cmd,
    system_opts(input, opts, sink, errs),
    function(res)
      local stdout, stderr, code = res.stdout or "", err_text(errs, opts), res.code
      if sink then
        stdout = sink_stdout(sink, opts)
        if sink.over then
          code, stderr = M.OUTPUT_LIMIT_CODE, over_message(sink)
        end
      end
      local signal = res.signal or 0
      if deadline and deadline.fired and not (sink and sink.over) then
        code, signal = 124, (signal ~= 0 and signal or 15)
      end
      settle(code == 0, stdout, code, stderr, signal)
    end
  )

  if not ok_spawn then
    settle(false, tostring(spawned), -1, "", 0)
    return { stop = function() end }
  end
  job = spawned

  -- The process is told to stop at `timeout_ms`, but the exit callback only
  -- fires once every pipe is closed: a descendant that keeps one open (the real
  -- git behind the Windows `cmd\git.exe` wrapper) would delay the answer for as
  -- long as it lives. Settle at the deadline (plus a short grace) instead.
  deadline = start_deadline(
    function()
      return job
    end,
    opts,
    function()
      -- SIGTERM went out; a child that ignores it, or a descendant that keeps the
      -- pipes open, gets the answer settled after the grace period.
      if not (deadline and deadline.timer) then
        return
      end
      deadline.timer:start(GRACE_MS, 0, function()
        if finished then
          return
        end
        kill_job(job, "sigkill")
        settle(
          false,
          sink and sink_stdout(sink, opts) or "",
          124,
          "timed out; the process did not exit",
          9
        )
      end)
    end
  )

  return {
    stop = function()
      -- (a finished run's pid may belong to somebody else by now)
      if finished then
        return
      end
      kill_job(job, "sigterm")
    end,
  }
end

return M
