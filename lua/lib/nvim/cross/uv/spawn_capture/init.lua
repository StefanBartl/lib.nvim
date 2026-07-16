---@module 'lib.nvim.cross.uv.spawn_capture'
--- Async spawn of an argv command with buffered stdout/stderr capture and an
--- optional timeout. Complements `cross.run`/`cross.run_argv` (blocking /
--- shell-string async) and `cross.uv.spawn_command`/`spawn_shell_command`
--- (fire-and-inherit-stdio): none of those cover "spawn argv, buffer output,
--- invoke a callback once, with an optional kill-on-timeout".

local function uv()
  return vim.uv or vim.loop
end

-- LuaJIT (Lua 5.1) has no `table.unpack`, only the global `unpack`.
local unpack_fn = table.unpack or unpack

---@param argv string[] Command and arguments, e.g. { "curl", "-sS", url }
---@param opts? { timeout_ms?: integer, cwd?: string, env?: table<string,string> }
---@param on_done fun(result: { ok: boolean, code: integer, signal: integer, stdout: string, stderr: string, timed_out: boolean })
return function(argv, opts, on_done)
  opts = opts or {}
  local loop = uv()

  local stdout_pipe = loop.new_pipe(false)
  local stderr_pipe = loop.new_pipe(false)
  local stdout_chunks, stderr_chunks = {}, {}
  local handle, pid
  local timer
  local done = false

  local function finish(code, signal, timed_out)
    if done then
      return
    end
    done = true
    if timer then
      pcall(timer.stop, timer)
      pcall(timer.close, timer)
      timer = nil
    end
    pcall(stdout_pipe.close, stdout_pipe)
    pcall(stderr_pipe.close, stderr_pipe)
    if handle then
      pcall(handle.close, handle)
    end
    local result = {
      ok = (not timed_out) and code == 0,
      code = code or -1,
      signal = signal or 0,
      stdout = table.concat(stdout_chunks),
      stderr = table.concat(stderr_chunks),
      timed_out = timed_out or false,
    }
    vim.schedule(function()
      on_done(result)
    end)
  end

  local spawn_opts = {
    args = { unpack_fn(argv, 2) },
    stdio = { nil, stdout_pipe, stderr_pipe },
    cwd = opts.cwd,
    env = opts.env,
  }

  handle, pid = loop.spawn(argv[1], spawn_opts, function(code, signal)
    finish(code, signal, false)
  end)

  if not handle then
    vim.schedule(function()
      on_done({ ok = false, code = -1, signal = 0, stdout = "", stderr = "failed to spawn: " .. argv[1], timed_out = false })
    end)
    return
  end

  stdout_pipe:read_start(function(err, data)
    if not err and data then
      stdout_chunks[#stdout_chunks + 1] = data
    end
  end)
  stderr_pipe:read_start(function(err, data)
    if not err and data then
      stderr_chunks[#stderr_chunks + 1] = data
    end
  end)

  if opts.timeout_ms then
    timer = loop.new_timer()
    timer:start(opts.timeout_ms, 0, function()
      if not done and handle then
        pcall(handle.kill, handle, "sigkill")
        finish(-1, 0, true)
      end
    end)
  end
end
