---@module 'lib.nvim.cross.run_argv'
--- Low-level argv-based process runner with stdin support.

local M = {}

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
    return false, (res.stderr ~= "" and res.stderr) or ("exit code " .. res.code)
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
---@param cmd string[]
---@param input? string
---@return boolean ok
---@return string output Captured stdout, both on success and failure
function M.run_blocking_captured(cmd, input)
  if vim.system then
    local ok, res = pcall(function()
      return vim.system(cmd, { text = true, stdin = input }):wait()
    end)
    if not ok then
      return false, tostring(res)
    end
    return res.code == 0, res.stdout or ""
  end

  local out = vim.fn.system(cmd, input or "")
  return vim.v.shell_error == 0, out
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
--- to touch buffers, windows and `vim.fn.*` from it. Both stdout and the exit
--- code are passed on; `code` lets a caller report a bare "exit code N" when
--- the process failed without writing anything.
---
--- The returned handle has a `stop()` method that sends SIGTERM. It is a no-op
--- on the legacy fallback path (Neovim < 0.10), where there is no job to kill.
---@param cmd string[]
---@param on_done fun(ok: boolean, output: string, code: integer)
---@param input? string
---@return { stop: fun() } handle
function M.run_async_captured(cmd, on_done, input)
  if not vim.system then
    -- Legacy fallback: no async process API. Run it the old way and report
    -- through the same callback so callers only ever need one shape.
    local out = vim.fn.system(cmd, input or "")
    local code = vim.v.shell_error
    vim.schedule(function()
      on_done(code == 0, out, code)
    end)
    return { stop = function() end }
  end

  -- vim.system raises synchronously when cmd[1] cannot be spawned at all
  -- (e.g. ENOENT) rather than delivering a failed SystemCompleted -- guard it
  -- so that case reaches on_done like every other failure, instead of an
  -- uncaught error escaping into the caller's stack.
  local ok_spawn, job = pcall(vim.system, cmd, { text = true, stdin = input }, function(res)
    vim.schedule(function()
      on_done(res.code == 0, res.stdout or "", res.code)
    end)
  end)

  if not ok_spawn then
    vim.schedule(function()
      on_done(false, tostring(job), -1)
    end)
    return { stop = function() end }
  end

  return {
    stop = function()
      pcall(function()
        job:kill("sigterm")
      end)
    end,
  }
end

return M
