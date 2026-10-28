---@module 'lib.nvim.system.job'
--- Thin wrapper around `vim.system` that restores plenary.job's line-buffered,
--- schedule-safe callback ergonomics (`on_stdout(err, line)` / `on_stderr(err,
--- line)`, invoked once per output line, already on the main loop) without
--- pulling in plenary.nvim as a dependency.
---
---   require("lib.nvim.system.job").start({
---     command = "head",
---     args = { "-n", "50", file },
---     on_stdout = function(_, line) ... end,
---     on_stderr = function(_, line) ... end,
---   })
---
--- `start_blocking`/`chain` are a different tier: raw stdout/stderr capture
--- instead of line callbacks. `vim.SystemObj:wait()` does not guarantee
--- `on_stdout`/`on_stderr` (`vim.schedule`-wrapped) have already fired by
--- the time it returns — `TESTS/system_job_spec.lua` needs an extra
--- `vim.wait` after `:wait()` for exactly this reason — so a caller that
--- needs output synchronously available on return needs raw capture
--- instead, exactly like `lib.nvim.net.curl.fetch_json_blocking` does for
--- the same reason.

require("lib.nvim.system.@types")

local lines = require("lib.nvim.system.lines")

local M = {}

--- Milliseconds between the SIGTERM of `kill()` and its SIGKILL (run_argv's deadline grace).
local KILL_GRACE_MS = 1500

---@internal
---@param opts Lib.System.Job.Opts
---@return string[]
local function build_cmd(opts)
  local cmd = { opts.command }
  for _, arg in ipairs(opts.args or {}) do
    table.insert(cmd, arg)
  end
  return cmd
end

---@internal
--- The `kill_tree` tier: `lib.nvim.cross.run_argv.run_async_captured` does the
--- process lifetime (deadline, SIGTERM then SIGKILL to the process group on
--- POSIX, `taskkill /T` on Windows), this adds the line callbacks and the
--- same SIGTERM -> SIGKILL escalation for `kill()`.
---@param opts Lib.System.Job.Opts
---@return Lib.System.Job.TreeHandle
local function start_tree(opts)
  local state = { done = false, killed = false, result = nil }

  --- A line callback that stays silent once the run was reported: run_argv settles
  --- at the deadline plus the grace period even when a descendant still holds the
  --- pipes, and its late output must not arrive after `on_exit`. All callbacks go
  --- through the same `vim.schedule` queue, so this drops exactly the late ones.
  ---@param cb fun(err: nil, line: string)|nil
  ---@return fun(err: string|nil, data: string|nil)|nil
  local function tap(cb)
    if not cb then
      return nil
    end
    return lines.buffered(function(err, line)
      if not state.done then
        cb(err, line)
      end
    end)
  end

  local runner = require("lib.nvim.cross.run_argv").run_async_captured(
    build_cmd(opts),
    function(_, stdout, code, stderr, signal)
      -- run_argv hands the reason of a spawn failure over in the stdout slot
      if code == -1 then
        stdout, stderr = "", (stdout ~= "" and stdout or stderr or "")
      end
      ---@type Lib.System.Job.TreeResult
      local result = {
        code = code,
        signal = signal or 0,
        stdout = stdout,
        stderr = stderr or "",
        -- run_argv's own deadline: exit code 124 with the signal it sent (a process that exits 124 by
        -- itself has signal 0)
        timed_out = code == 124 and (signal or 0) ~= 0,
        killed = state.killed,
      }
      state.done, state.result = true, result
      if opts.on_exit then
        opts.on_exit(result)
      end
    end,
    opts.stdin,
    {
      timeout_ms = opts.timeout_ms,
      cwd = opts.cwd,
      env = opts.env,
      on_stdout = tap(opts.on_stdout),
      on_stderr = tap(opts.on_stderr),
      -- the lines are the caller's; `result.stdout` stays empty instead of growing without bound
      keep_stdout = opts.on_stdout == nil,
    }
  )

  -- Methods work with `.` and with `:` (`vim.SystemObj` is used as `obj:wait(ms)`).
  ---@type Lib.System.Job.TreeHandle
  local handle = {}
  local escalation
  function handle.kill()
    if state.done or state.killed then
      return
    end
    state.killed = true
    runner.stop("sigterm")
    -- whatever ignores the SIGTERM gets SIGKILL after the same grace period as the deadline's
    escalation = (vim.uv or vim.loop).new_timer()
    escalation:start(KILL_GRACE_MS, 0, function()
      escalation:close()
      if not state.done then
        runner.stop("sigkill")
      end
    end)
  end
  function handle.is_done()
    return state.done
  end
  function handle.wait(a, b)
    local timeout_ms = type(a) == "table" and b or a
    vim.wait(timeout_ms or 2 ^ 31 - 1, function()
      return state.done
    end, 10)
    return state.result
  end
  return handle
end

--- Start a command, streaming stdout/stderr to the given callbacks one line
--- at a time (each call already wrapped in `vim.schedule`).
---
--- With `opts.kill_tree = true` the process tree ends on `opts.timeout_ms` and
--- on `handle.kill()`, not only the direct child (a `.sh` step's tools, a child
--- editor's language servers), and the return value is a
--- `Lib.System.Job.TreeHandle` instead of the `vim.SystemObj`; `cwd`, `env`,
--- `stdin` and `on_exit` apply. Without it `vim.system`'s own handle is
--- returned and its `kill()` reaches the direct child only.
---@param opts Lib.System.Job.Opts
---@return vim.SystemObj|Lib.System.Job.TreeHandle
function M.start(opts)
  if opts.kill_tree then
    return start_tree(opts)
  end
  return vim.system(build_cmd(opts), {
    stdout = lines.buffered(opts.on_stdout),
    stderr = lines.buffered(opts.on_stderr),
  })
end

--- Run a command to completion, blocking the caller, and return its full
--- captured output (raw-capture tier — see the module header for why this
--- does not go through `on_stdout`/`on_stderr`).
---@param opts Lib.System.Job.Opts
---@return vim.SystemCompleted
function M.start_blocking(opts)
  return vim
    .system(build_cmd(opts), { text = true, timeout = opts.timeout_ms, stdin = opts.stdin })
    :wait(opts.timeout_ms)
end

--- Run `job_specs` in sequence, stopping at the first non-zero exit —
--- plenary's `Job.chain`/`and_then*`/`after_success` chaining, in the
--- shape `vim.system` actually supports: async, callback-driven (each step
--- completes before the next one starts, no polling), raw-capture (not
--- line-buffered) tier throughout. Unless a spec sets its own
--- `opts.stdin`, it defaults to the previous step's captured stdout — the
--- pragmatic, `vim.system`-shaped version of plenary's stdin-writer
--- chaining (a full streaming pipe between two live processes is not
--- something `vim.system`'s API offers).
---@param job_specs Lib.System.Job.Opts[]
---@param on_done fun(ok: boolean, results: vim.SystemCompleted[])
function M.chain(job_specs, on_done)
  local results = {}

  ---@param i integer
  ---@param prev_stdout string|nil
  local function run_step(i, prev_stdout)
    local spec = job_specs[i]
    if not spec then
      on_done(true, results)
      return
    end

    local stdin = spec.stdin
    if stdin == nil then
      stdin = prev_stdout
    end

    vim.system(
      build_cmd(spec),
      { text = true, timeout = spec.timeout_ms, stdin = stdin },
      function(obj)
        results[i] = obj
        if obj.code ~= 0 then
          on_done(false, results)
          return
        end
        run_step(i + 1, obj.stdout)
      end
    )
  end

  run_step(1, nil)
end

---@type Lib.System.Job
return M
