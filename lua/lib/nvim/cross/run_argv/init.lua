---@module 'lib.nvim.cross.run_argv'
--- Low-level argv-based process runner with stdin support.
---
--- Process lifetime (timeout, output cap, `stop()`): on POSIX a child that one of
--- these can kill is started in a session and process group of its own
--- (`vim.system` `detach = true`, libuv `setsid()`; the group id is the child's
--- pid), and the kill signals the WHOLE group, so the grandchildren of the child
--- (the `git-remote-http` behind `git fetch`, a build tool's workers, whatever a
--- wrapper script starts) die with it instead of living on with PPID 1 and the
--- output pipes open. That holds while the child itself still runs when the kill
--- comes: the group of a child that has exited is left alone, because its id may
--- have been reused (`signal_group`). On Windows the whole tree is killed with
--- `taskkill /T` instead and nothing is detached. What detaching changes for the
--- child is documented at `DETACH` below.

local M = {}

local uv = vim.uv or vim.loop

-- Decided once: `kill_tree` runs in libuv callbacks (the deadline timer, the
-- stdout handler), where `vim.fn.*` is not allowed.
local IS_WIN = (uv.os_uname().sysname or ""):find("Windows", 1, true) ~= nil

--- Whether a child that can be killed is started in a process group of its own
--- (POSIX only; Windows has `taskkill /T` for the tree and a detached Windows
--- process would get its own console).
---
--- What `detach = true` means for such a child (measured by hand on Linux with a
--- pty as the controlling terminal, Neovim 0.11; the specs do not cover these
--- terminal effects, the headless spec runner has no controlling terminal to tell
--- a detached child from an attached one -- they only check that the child leads a
--- process group of its own):
---   * It has no controlling terminal (`setsid()`): opening `/dev/tty` fails with
---     `ENXIO` at once. A program that wants to prompt there (`ssh` for a
---     passphrase or host-key question, `gpg` for a pinentry, `git` for a
---     username without `GIT_TERMINAL_PROMPT=0`) now fails fast instead of
---     writing the prompt into the TUI and waiting for a key nobody can type.
---     Prompts that go through stdin/stdout are not affected (stdin is a pipe).
---   * It gets no terminal-generated signals (SIGINT of Ctrl-C, SIGHUP when the
---     terminal goes away): it is stopped only by us -- the deadline, the output
---     cap, `stop()` -- or by its own end. A `:qa!` or a closed terminal does not
---     kill it, which is no change for `:qa!` (Neovim does not kill `vim.system`
---     children on exit, detached or not) and means that a closed terminal no
---     longer takes a still running child with it.
---   * It does not keep Neovim from exiting: libuv documents that a detached
---     child keeps the loop of a plain libuv program alive unless the handle is
---     unref'd, but Neovim leaves with `exit()`, not by draining its loop. Measured:
---     `:qa!` with a running detached child took the same time (about 0.21 s
---     headless, about 1.3 s in a pty) as with an attached one, so the handle is
---     deliberately not unref'd (that would also need `vim.system` internals).
local DETACH = not IS_WIN

--- Jobs this module started with `detach = true`, i.e. whose pid is the id of a
--- process group that only this module's child (and its descendants) belong to.
--- Only such a group is ever signalled: `kill(-pid)` for a child that shares the
--- process group of Neovim would signal Neovim itself and its siblings. Weak keys:
--- an entry does not outlive its job.
---@type table<table, boolean>
local OWN_GROUP = setmetatable({}, { __mode = "k" })

--- Jobs for which a follow-up SIGKILL to the process group is still owed: the
--- deadline sent its SIGTERM to the group while the leader was alive, and the
--- grace timer will send the SIGKILL, which must also reach the group when the
--- leader has exited on the SIGTERM by then (a descendant that ignores the SIGTERM
--- and holds the pipes). Set by the deadline's SIGTERM only -- never by `stop()` or
--- the output cap -- and cleared by the next SIGKILL, so the exception to the
--- "leader reaped: leave the group alone" rule lasts for the grace period
--- (`GRACE_MS`) of one run; see `signal_group`. Weak keys: an entry does not
--- outlive its job.
---@type table<table, boolean>
local FOLLOW_UP = setmetatable({}, { __mode = "k" })

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
---@field timeout_ms? integer Kill the process (SIGTERM) after this many milliseconds; the run then ends with exit code `124`, the `timeout(1)` convention, whatever the child made of the signal (a child that handles SIGTERM and exits 0, as Neovim does, is a timeout all the same). The deadline is a timer of our own, started once the process is spawned; whatever is still running `1500` ms after the SIGTERM (a child that ignores it) is killed with SIGKILL. The process tree is killed: on POSIX the child runs in a process group of its own (`detach`, see `DETACH`) and both signals go to that group, so grandchildren die with it, the output pipes close at once and the async runner answers at the deadline; on Windows `taskkill /T` kills the tree. On POSIX that holds while the child itself is still running at the deadline: the descendants of a child that has exited already (or that left its group with `setsid()`) are not signalled, because the group id of an empty group may have been reused (see `signal_group`); the async runner then answers at the deadline plus the grace period (code `124`, signal `9`). A run with a timeout is detached on POSIX, i.e. the child has no controlling terminal (`/dev/tty` prompts fail fast) and gets no terminal-generated SIGINT/SIGHUP. The async runner settles at the deadline plus the `1500` ms grace period at the latest, the blocking runner returns once `wait()` gives up. Needs `vim.system`; the legacy fallback ignores it.
---@field max_output_bytes? integer Stop the process once its stdout exceeds this many bytes: the run then ends with exit code `125` (`M.OUTPUT_LIMIT_CODE`), `stdout` holds what fitted and `stderr` says why. A process whose output is the data (`git log` of a repository somebody else wrote) can print gigabytes from a tiny input; without a cap all of it is collected in memory. The kill (SIGKILL) goes to the whole process group on POSIX while the child is still running, like the timeout's (and the run is detached then). Needs `vim.system`; the legacy fallback ignores it.
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
--- POSIX: send `signal` to the process GROUP of a job this module started
--- detached. Returns `true` when the signal went out.
---
--- Why this is safe, and when it is not attempted. A process group id stays
--- valid for as long as any member lives, and POSIX forbids reusing a pid number
--- while a group of that number exists, so while the leader (the direct child) is
--- alive -- or while a member that outlived it is -- `-pid` can only name OUR
--- group. Once the group is empty the number is free again and may belong to a
--- stranger that happened to become a group leader, exactly the pid-reuse hazard
--- the `is_closing()` guard of `kill_job` exists for. Nothing here can tell
--- whether a member is left once the leader has been reaped, so:
---   * Leader alive (its `vim.system` handle is not closing): always signalled.
---   * Leader reaped: signalled only for the follow-up SIGKILL the deadline owes
---     (`FOLLOW_UP`) -- a leader that exited on the SIGTERM while a descendant
---     ignores it and holds the pipes. That exception lasts from the deadline's
---     SIGTERM to the SIGKILL one grace period (1.5 s) later, and is used up by the
---     first SIGKILL; a stranger would have to get this very pid and become a
---     group leader within it.
---   * Leader reaped, no follow-up owed: left alone, as before this module used
---     groups. That is a child that had exited on its own when the deadline, the
---     output cap or `stop()` came, or one that exited on a `stop()` before the
---     deadline (the deadline's SIGTERM then finds a reaped leader, and nothing
---     is owed after a refused signal). Its descendants are not signalled; the run
---     is still answered (the async runner at the deadline plus the grace period).
---   * A pid of 0 or 1 is never used as a group id: `kill(0)` is the process group
---     of Neovim itself and `kill(-1)` is every process we may signal.
---@param job table  The `vim.system` object.
---@param signal string
---@param owe_follow_up? boolean  The caller will send a SIGKILL after the grace period (the deadline's SIGTERM): remember it, see `FOLLOW_UP`.
---@return boolean sent
local function signal_group(job, signal, owe_follow_up)
  local pid = job.pid
  if IS_WIN or not pid or pid <= 1 or not OWN_GROUP[job] then
    return false
  end
  local leader_alive = not (job.is_closing and job:is_closing())
  if not leader_alive and not FOLLOW_UP[job] then
    return false
  end
  if signal == "sigkill" then
    -- the last signal there is: nothing is owed after it, sent or not
    FOLLOW_UP[job] = nil
  end
  -- (a negative pid addresses the group; `uv.kill` returns 0, or nil + reason)
  local sent = uv.kill(-pid, signal) == 0
  if sent and owe_follow_up and leader_alive then
    FOLLOW_UP[job] = true
  end
  return sent
end

---@internal
--- Best effort: kill a process AND its children. `vim.system`'s own timeout and
--- `stop()` signal only the direct child.
---   * POSIX: the signal goes to the child's process group (`signal_group`), so the
---     descendants get it too; when the group cannot be signalled (it is gone, or
---     the job is not one of ours) the direct child is signalled as before.
---   * Windows: the `git.exe` of `cmd\` is a thin wrapper whose real git keeps
---     running (and keeps the pipes open). `taskkill /T` finds the descendants
---     through the PARENT, so the parent must still be alive when it runs: the
---     signal to the direct child is sent only after `taskkill` has finished (and
---     straight away when it cannot be started).
--- An exited process is never signalled by pid: its pid may already belong to
--- somebody else (`/F` would kill that), and `/T` finds descendants only through a
--- live parent anyway. The one exception is the follow-up group signal of
--- `signal_group`.
---@param job table|nil  The `vim.system` object.
---@param signal string
---@param owe_follow_up? boolean  See `signal_group`: the deadline's SIGTERM.
local function kill_job(job, signal, owe_follow_up)
  if not job then
    return
  end
  if signal_group(job, signal, owe_follow_up) then
    return
  end
  if job.is_closing and job:is_closing() then
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
--- Best effort, no signal to the direct child afterwards: for a run that already
--- gave up waiting. Windows: `taskkill /T`; POSIX: SIGKILL to the process group
--- (under the rules of `signal_group`). On POSIX this is normally redundant -- the
--- grace timer of the deadline has sent that SIGKILL long before `wait()` gives up
--- (it does so after `timeout_ms + GRACE_MS`, then waits as long again) -- and is
--- a safety net for a timer that did not run.
---@param job table|nil  The `vim.system` object.
local function kill_tree(job)
  if not job or not job.pid then
    return
  end
  if not IS_WIN then
    signal_group(job, "sigkill")
    return
  end
  if job.is_closing and job:is_closing() then
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
--- Whether `value` is a usable `timeout_ms` / `max_output_bytes`: a number that is
--- neither NaN nor negative. One predicate for the deadline, the output cap and
--- `has_kill_path`, so that a run is only detached (given a process group of its
--- own) when one of them is really armed.
---@param value any
---@return boolean
local function is_limit(value)
  return type(value) == "number" and value == value and value >= 0
end

---@internal
--- Collect stdout ourselves when a cap is set, so that a runaway process is
--- stopped instead of being read to the end.
---@param opts Lib.RunArgv.Opts|nil
---@param kill fun()
---@return table|nil sink
local function new_sink(opts, kill)
  local cap = opts and opts.max_output_bytes
  if not is_limit(cap) then
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
---
--- After the SIGTERM the same timer is armed once more for `GRACE_MS`: a child (or
--- a descendant) that did not give up by then gets SIGKILL -- in every runner, so
--- that a blocking run does not depend on `job:wait()` (whose own SIGKILL at
--- `timeout_ms + GRACE_MS` reaches the direct child only). On POSIX both signals go
--- to the whole process group (`kill_job`).
---@class Lib.RunArgv.Deadline
---@field fired boolean SIGTERM was sent because the deadline passed.
---@field timer uv.uv_timer_t|nil

---@param get_job fun(): table|nil
---@param opts Lib.RunArgv.Opts|nil
---@param on_grace fun()|nil Runs (in the libuv callback) after the SIGKILL that ends the grace period.
---@return Lib.RunArgv.Deadline|nil
local function start_deadline(get_job, opts, on_grace)
  local ms = opts and opts.timeout_ms
  if not is_limit(ms) then
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
    -- (the SIGKILL below follows this SIGTERM: it may reach the group of a leader that
    -- exited on it, see `FOLLOW_UP`)
    kill_job(job, "sigterm", true)
    -- (`stop_deadline` may have run meanwhile: the timer is gone then)
    if not d.timer then
      return
    end
    d.timer:start(GRACE_MS, 0, function()
      kill_job(job, "sigkill")
      if on_grace then
        on_grace()
      end
    end)
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
---@param managed boolean The run has a kill path (deadline, output cap, `stop()`): on POSIX the child gets a process group of its own.
---@return table
local function system_opts(input, opts, sink, errs, managed)
  opts = opts or {}
  return {
    -- see `DETACH`; a run nothing can kill keeps the terminal and its signals
    detach = managed and DETACH or nil,
    text = not opts.binary,
    stdin = input,
    env = opts.env,
    cwd = opts.cwd,
    stdout = sink and sink.handler or nil,
    stderr = errs and errs.handler or nil,
  }
end

---@internal
--- `vim.system` plus the bookkeeping `signal_group` relies on: a job started
--- detached owns the process group of its pid.
---@param cmd string[]
---@param sys_opts table  From `system_opts`.
---@param on_exit? fun(res: table)
---@return table job  The `vim.system` object.
local function spawn(cmd, sys_opts, on_exit)
  local job = vim.system(cmd, sys_opts, on_exit)
  if sys_opts.detach then
    OWN_GROUP[job] = true
  end
  return job
end

---@internal
--- Whether a run of `opts` can be killed by its own deadline or output cap (the
--- async runner always can: `stop()`). A `timeout_ms` or `max_output_bytes` that
--- `start_deadline` / `new_sink` ignore (NaN, negative) arms nothing.
---@param opts Lib.RunArgv.Opts|nil
---@return boolean
local function has_kill_path(opts)
  return opts ~= nil and (is_limit(opts.timeout_ms) or is_limit(opts.max_output_bytes))
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
      job = spawn(cmd, system_opts(input, opts, sink, errs, has_kill_path(opts)))
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
    job = spawn(cmd, system_opts(input, opts, sink, errs, has_kill_path(opts)))
    deadline = start_deadline(function()
      return job
    end, opts)
    -- `wait(ms)` that runs out sends SIGKILL to the direct child; the SIGKILL of the
    -- whole group is the deadline timer's (`start_deadline`), a moment earlier or later.
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
--- With `opts.timeout_ms` the process is sent SIGTERM at the deadline -- on POSIX
--- the whole process group of the child, so its grandchildren die with it, the
--- pipes close and `on_done` is called right away; on Windows the tree is killed
--- with `taskkill /T`. Whatever ignores the SIGTERM is killed (SIGKILL, again the
--- whole group) after a short grace period, and when even that does not close the
--- pipes (a Windows descendant, or on POSIX a descendant that left the group with
--- `setsid()` or that outlived a child that had exited before the deadline: those
--- are not signalled, see `signal_group`) `on_done` gets code `124`, signal `9` at
--- that point. The exit code is `124` in every case.
---
--- The child of this runner is always started detached on POSIX (see `DETACH`):
--- in a process group of its own, without a controlling terminal.
---
--- The returned handle has a `stop()` method that sends SIGTERM to the process
--- group of the child (on Windows it kills the process tree). It is a no-op on the
--- legacy fallback path (Neovim < 0.10), where there is no job to kill.
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
    spawn,
    cmd,
    system_opts(input, opts, sink, errs, true),
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
  -- fires once every pipe is closed. On POSIX the signal reaches the whole process
  -- group, so the pipes close with it and the exit callback answers right away;
  -- the settle below is for what a signal does not reach: a child that ignores
  -- SIGTERM (it gets SIGKILL after the grace period, and is settled right after
  -- it), a descendant that left the group or outlived an already exited child
  -- (POSIX, see `signal_group`), or, on Windows, a descendant that keeps a pipe
  -- open (the real git behind the `cmd\git.exe` wrapper). Settle at the deadline
  -- plus the grace period instead of waiting for it.
  deadline = start_deadline(function()
    return job
  end, opts, function()
    if finished then
      return
    end
    settle(
      false,
      sink and sink_stdout(sink, opts) or "",
      124,
      "timed out; the process did not exit",
      9
    )
  end)

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
