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

--- Start a command, streaming stdout/stderr to the given callbacks one line
--- at a time (each call already wrapped in `vim.schedule`).
---@param opts Lib.System.Job.Opts
---@return vim.SystemObj
function M.start(opts)
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
