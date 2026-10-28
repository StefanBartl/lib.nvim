-- TESTS/system_job_kill_tree_spec.lua — lib.nvim.system.job.start({ kill_tree = true })
--
-- The child is a headless Neovim that starts a sleeping Neovim GRANDCHILD (no shell, so the same
-- spec runs on Windows, Linux and macOS), writes the grandchild's pid to a file and then sleeps
-- itself. A timeout or `kill()` must end both; `vim.system`'s own kill reaches the child only.

return function(H)
  local eq, ok = H.eq, H.ok
  local uv = vim.uv or vim.loop
  local job = require("lib.nvim.system.job")

  local nvim = vim.v.progpath

  --- Write `lines` to a fresh temp file; its path.
  ---@param lines string[]
  ---@return string
  local function script(lines)
    local path = vim.fn.tempname() .. ".lua"
    vim.fn.writefile(lines, path)
    return path
  end

  local sleeper = script({ "vim.wait(60000, function() return false end, 100)" })
  -- arg[1] = pid file, arg[2] = sleeper script.
  -- Windows: libuv puts every child into a job object that is killed with its parent, so a grandchild
  -- started the normal way dies with the child anyway and would prove nothing. Detached, it is outside
  -- that job and only linked to the tree by its parent pid: only `taskkill /T` reaches it. POSIX: NOT
  -- detached, so it stays in the child's process group (detached would be a `setsid()` daemon, which
  -- no group kill reaches, documented in run_argv).
  local parent = script({
    "local g = vim.system({ vim.v.progpath, '--headless', '-u', 'NONE', '-i', 'NONE', '-l', _G.arg[2] },",
    "  { detach = vim.fn.has('win32') == 1 })",
    "local f = assert(io.open(_G.arg[1], 'w'))",
    "f:write(tostring(g.pid) .. '\\n')",
    "f:close()",
    "io.stdout:write('started\\n')",
    "io.stdout:flush()",
    "vim.wait(60000, function() return false end, 100)",
  })

  ---@param path string
  ---@return integer|nil
  local function read_pid(path)
    local f = io.open(path, "r")
    if not f then
      return nil
    end
    local text = f:read("*a") or ""
    f:close()
    return tonumber(text:match("^(%d+)\n"))
  end

  --- A live process. A zombie (killed, not yet reaped by whatever adopted it; PID 1 of a container often
  --- never does) is dead, as in run_argv_spec.
  ---@param pid integer
  ---@return boolean
  local function alive(pid)
    if uv.kill(pid, 0) ~= 0 then
      return false
    end
    local f = io.open(("/proc/%d/stat"):format(pid), "r")
    if f then
      local stat = f:read("*a") or ""
      f:close()
      if stat:match("%) (%a)") == "Z" then
        return false
      end
    end
    return true
  end

  ---@param p string
  ---@return string
  local function real(p)
    return vim.fs.normalize(uv.fs_realpath(p) or p)
  end

  --- Wait for the pid file; the grandchild pid.
  ---@param path string
  ---@return integer
  local function grandchild(path)
    vim.wait(20000, function()
      return read_pid(path) ~= nil
    end, 20)
    local pid = read_pid(path)
    ok(pid ~= nil, "the child started its grandchild (pid file " .. path .. ")")
    return pid --[[@as integer]]
  end

  --- The grandchild is gone soon after the run ended; killed in any case so a red spec leaves nothing behind.
  ---@param pid integer
  ---@param msg string
  local function expect_dead(pid, msg)
    local dead = vim.wait(10000, function()
      return not alive(pid)
    end, 50)
    if not dead then
      pcall(uv.kill, pid, "sigkill")
    end
    ok(dead, msg .. " (grandchild pid " .. pid .. " still alive)")
  end

  -- (a) timeout: exit code 124, timed_out, lines delivered, the grandchild ends with the tree
  do
    local pidfile = vim.fn.tempname()
    local lines, exited = {}, nil
    local handle = job.start({
      command = nvim,
      args = { "--headless", "-u", "NONE", "-i", "NONE", "-l", parent, pidfile, sleeper },
      kill_tree = true,
      timeout_ms = 4000,
      on_stdout = function(_, line)
        lines[#lines + 1] = line
      end,
      on_exit = function(r)
        exited = r
      end,
    })
    local gpid = grandchild(pidfile)
    ok(alive(gpid), "timeout: the grandchild runs before the deadline")
    local r = handle.wait(30000)
    ok(r ~= nil, "timeout: the run ends")
    eq(r and r.code, 124, "timeout: exit code 124")
    eq(r and r.timed_out, true, "timeout: timed_out")
    eq(r and r.killed, false, "timeout: not killed by kill()")
    vim.wait(1000, function()
      return exited ~= nil
    end, 10)
    eq(exited, r, "timeout: on_exit gets the same result")
    eq(lines[1], "started", "timeout: stdout arrives line by line")
    eq(handle.is_done(), true, "timeout: is_done")
    expect_dead(gpid, "timeout: the grandchild is killed with the tree")
  end

  -- (b) kill(): the tree ends, killed = true
  do
    local pidfile = vim.fn.tempname()
    local handle = job.start({
      command = nvim,
      args = { "--headless", "-u", "NONE", "-i", "NONE", "-l", parent, pidfile, sleeper },
      kill_tree = true,
    })
    local gpid = grandchild(pidfile)
    eq(handle.is_done(), false, "kill: still running")
    handle:kill() -- colon style, as on a vim.SystemObj
    local r = handle:wait(30000)
    ok(r ~= nil, "kill: the run ends")
    eq(r and r.killed, true, "kill: killed")
    eq(r and r.timed_out, false, "kill: not a timeout")
    expect_dead(gpid, "kill: the grandchild is killed with the tree")
  end

  -- (c) a normal run: exit code, stdout/stderr lines, cwd, env, stdin
  do
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local echo = script({
      "io.stdout:write(vim.uv.cwd() .. '\\n' .. (vim.uv.os_getenv('LIB_JOB_SPEC') or '') .. '\\n')",
      "io.stdout:write(io.read('*a'))",
      "io.stderr:write('err line\\n')",
      "os.exit(3)",
    })
    local out, err = {}, {}
    local r = job
      .start({
        command = nvim,
        args = { "--headless", "-u", "NONE", "-i", "NONE", "-l", echo },
        kill_tree = true,
        cwd = dir,
        env = { LIB_JOB_SPEC = "yes" },
        stdin = "from stdin\n",
        on_stdout = function(_, line)
          out[#out + 1] = line
        end,
        on_stderr = function(_, line)
          err[#err + 1] = line
        end,
      })
      .wait(30000)
    eq(r and r.code, 3, "normal: the exit code")
    eq(r and r.timed_out, false, "normal: no timeout")
    eq(real(out[1] or ""), real(dir), "normal: cwd")
    eq(out[2], "yes", "normal: env")
    eq(out[3], "from stdin", "normal: stdin")
    eq(err[1], "err line", "normal: stderr line")
    eq(r and r.stdout, "", "normal: with on_stdout nothing is collected a second time")
    ok(r and r.stderr:find("err line", 1, true) ~= nil, "normal: stderr is collected")

    local plain = job
      .start({
        command = nvim,
        args = { "--headless", "-u", "NONE", "-i", "NONE", "-l", echo },
        kill_tree = true,
        stdin = "collected\n",
      })
      .wait(30000)
    ok(
      plain and plain.stdout:find("collected", 1, true) ~= nil,
      "normal: without on_stdout stdout is collected"
    )
  end

  -- (e) POSIX: kill() sends SIGTERM first, SIGKILL after the grace period to a child that ignores it
  -- (Windows: taskkill /F is final)
  if vim.fn.has("win32") == 0 and vim.fn.executable("sh") == 1 then
    local ready = false
    local handle = job.start({
      command = "sh",
      args = { "-c", "trap '' TERM; echo ready; while :; do sleep 1; done" },
      kill_tree = true,
      on_stdout = function(_, line)
        ready = ready or line == "ready"
      end,
    })
    ok(
      vim.wait(10000, function()
        return ready
      end, 20),
      "escalation: the trap is installed"
    )
    local t0 = uv.hrtime()
    handle.kill()
    local r = handle.wait(15000)
    local ms = (uv.hrtime() - t0) / 1e6
    ok(r ~= nil, "escalation: a child that ignores SIGTERM still ends")
    eq(r and r.signal, 9, "escalation: by SIGKILL")
    eq(r and r.code, 137, "escalation: exit code 128 + 9")
    ok(
      ms >= 1200,
      "escalation: SIGTERM first, SIGKILL only after the grace period (" .. ms .. " ms)"
    )
    ok(ms < 8000, "escalation: within the grace period (" .. ms .. " ms)")

    -- a killed run is not a success: 128 + 15, not the 0 libuv reports for a signalled child
    local plain = job.start({ command = "sh", args = { "-c", "sleep 30" }, kill_tree = true })
    vim.wait(300, function()
      return false
    end, 50)
    plain:kill()
    local pr = plain:wait(10000)
    eq(pr and pr.signal, 15, "kill: SIGTERM ended it")
    eq(pr and pr.code, 143, "kill: exit code 128 + 15, never 0")

    -- the leader dies of the SIGTERM, a descendant ignores it and holds the pipes: the follow-up SIGKILL
    -- still reaches the process group, the run ends and the descendant is gone
    local stubborn
    local h2 = job.start({
      command = "sh",
      args = { "-c", "sh -c 'trap \"\" TERM; echo ready $$; exec sleep 30' & wait" },
      kill_tree = true,
      on_stdout = function(_, line)
        stubborn = stubborn or tonumber(line:match("^ready (%d+)$"))
      end,
    })
    ok(
      vim.wait(10000, function()
        return stubborn ~= nil
      end, 20),
      "stubborn: the descendant runs"
    )
    h2.kill()
    local r2 = h2.wait(10000)
    ok(r2 ~= nil, "stubborn: the run ends although the leader died first")
    expect_dead(stubborn, "stubborn: the descendant that ignored SIGTERM is killed")
  end

  -- `handle:wait()` without a limit (the vim.SystemObj idiom) returns the result instead of raising
  do
    local h = job.start({
      command = nvim,
      args = { "--headless", "-u", "NONE", "-i", "NONE", "-l", script({ "os.exit(0)" }) },
      kill_tree = true,
    })
    local okw, r = pcall(h.wait, h)
    ok(okw, "wait(): no error (" .. tostring(r) .. ")")
    eq(type(r) == "table" and r.code, 0, "wait(): the result")
  end

  -- lines that arrive after the run was reported are dropped, and kill() after the end is no kill
  do
    local saved = package.loaded["lib.nvim.cross.run_argv"]
    package.loaded["lib.nvim.cross.run_argv"] = {
      run_async_captured = function(_, on_done, _, o)
        local finished = false
        -- the order of the real runner: the taps run in the pipe callback, on_done is scheduled
        -- (`settle`), a descendant's output can still come after it
        vim.schedule(function()
          o.on_stdout(nil, "early\n")
          finished = true
          -- kill() in the window where the run has ended but on_done is still on its way
          if _G.__job_spec_kill then
            _G.__job_spec_kill()
          end
          vim.schedule(function()
            on_done(true, "", 0, "", 0)
            o.on_stdout(nil, "late\n")
            o.on_stdout(nil, nil)
          end)
        end)
        return {
          stop = function() end,
          is_finished = function()
            return finished
          end,
        }
      end,
    }
    local seen = {}
    local h = job.start({
      command = "x",
      kill_tree = true,
      on_stdout = function(_, line)
        seen[#seen + 1] = line
      end,
    })
    _G.__job_spec_kill = function()
      h.kill()
    end
    local r = h.wait(5000)
    vim.wait(200, function()
      return false
    end, 10)
    _G.__job_spec_kill = nil
    package.loaded["lib.nvim.cross.run_argv"] = saved
    eq(#seen, 1, "late lines: only the line before on_exit")
    eq(seen[1], "early", "late lines: ... the early one")
    eq(r and r.killed, false, "kill() after the end, before on_exit: not killed")
  end

  -- (d) a command that cannot start: code -1, on_exit still once
  do
    local calls = 0
    local r = job
      .start({
        command = "lib-nvim-does-not-exist-xyz",
        kill_tree = true,
        on_exit = function()
          calls = calls + 1
        end,
      })
      .wait(10000)
    eq(r and r.code, -1, "missing command: code -1")
    eq(r and r.stdout, "", "missing command: stdout empty")
    ok(r and r.stderr ~= "", "missing command: the reason is in stderr")
    vim.wait(200, function()
      return false
    end, 10)
    eq(calls, 1, "missing command: on_exit once")
  end
end
