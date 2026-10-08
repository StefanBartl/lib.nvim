-- TESTS/git_sync_cancel_spec.lua -- how a killed or unspawnable git reaches fetch/pull/push/update_async
--
-- `git_sync_spec.lua` pins stop() during pull_async's before- and after-hash reads. Not covered
-- there: stop() during the pull itself, stop() on update_async (including a fetch that finished
-- while the stop() landed), and what the verbs report for a git that was killed by a signal or
-- cannot be spawned at all.
--
-- The process runner (`run_argv.run_async_captured`) is faked wherever the outcome has to be
-- exact. A kill reaches the callback in two shapes, neither of which is `(false, "", 143, "")`:
--   Windows: exit code 1 (nvim 0.12.2: with signal 15)  -> (false, "", 1, "", 0 | 15)
--   POSIX:   exit code 0 with the signal that killed it -> (true,  "", 0, "", 15)  (`ok` is true!)
-- "Exit code 143" (128 + signal) is what this library reports for the POSIX shape only. On
-- Windows libuv can deliver the exit late, after helper processes such as git-remote-http
-- have ended, so a real stop() is not guaranteed to be followed by on_done promptly there.

-- Module level on purpose: the cleanup at the bottom must see the directories of a run that raised.
local created = {} ---@type string[]

local function run(H)
  local git = require("lib.nvim.git")
  local run_argv = require("lib.nvim.cross.run_argv")
  local original = run_argv.run_async_captured

  local function tmpdir(suffix)
    local dir = vim.fn.tempname() .. suffix
    vim.fn.mkdir(dir, "p")
    created[#created + 1] = dir
    return dir
  end

  local function wait_for(pred)
    -- Long on purpose: a git call takes seconds on a busy machine, and a pass costs nothing.
    vim.wait(60000, pred, 10)
    return pred()
  end

  --- The git subcommand an argv runs.
  local function verb_of(argv)
    for _, v in ipairs({ "fetch", "pull", "push", "rev-parse", "status", "show", "blame" }) do
      if vim.tbl_contains(argv, v) then
        return v
      end
    end
  end

  local function count(list, what)
    local n = 0
    for _, v in ipairs(list) do
      if v == what then
        n = n + 1
      end
    end
    return n
  end

  -- on_done arguments of a job that was killed: (ok, stdout, code, stderr, signal)
  local KILLED = {
    { name = "windows shape", args = { false, "", 1, "", 0 } },
    { name = "posix shape", args = { true, "", 0, "", 15 } },
  }

  --- A fake `run_async_captured`. `plan[verb]` is what a call of that git verb does:
  ---   "real"  runs the real job
  ---   a list  answers (via vim.schedule) with those on_done arguments
  ---   "park"  (also the default) keeps its on_done in `rec.parked[verb]` for the spec to fire;
  ---           the handle it returns records `rec.stopped[verb]`
  ---@param plan table<string, string|table>
  local function fake_runner(plan)
    local rec = { dispatched = {}, parked = {}, stopped = {} }
    rec.fn = function(argv, on_done, ...)
      local verb = verb_of(argv)
      rec.dispatched[#rec.dispatched + 1] = verb
      local step = plan[verb] or "park"
      if step == "real" then
        return original(argv, on_done, ...)
      end
      if type(step) == "table" then
        vim.schedule(function()
          on_done(step[1], step[2], step[3], step[4], step[5])
        end)
        return {
          stop = function() end,
        }
      end
      rec.parked[verb] = on_done
      return {
        stop = function()
          rec.stopped[verb] = true
        end,
      }
    end
    return rec
  end

  -- ── pull_async: stop() while `git pull` itself runs ─────────────────────
  -- Every stage callback starts with the `cancelled` check; the before-hash and the after-hash
  -- stage have a spec in git_sync_spec.lua, the pull stage had none. Without it the Windows
  -- shape reports on_done(false, ...) for a pull the caller cancelled, and the POSIX shape
  -- starts an after-hash read for it.
  for _, shape in ipairs(KILLED) do
    local label = "pull_async(stopped during the pull, " .. shape.name .. ")"
    local repo = tmpdir("-git-cancel-pull")
    vim.system({ "git", "-C", repo, "init", "-q", "-b", "main" }):wait()

    -- The before-hash read is real (it fails in an empty repository, which is fine: the pull
    -- still starts); the pull is parked.
    local rec = fake_runner({ ["rev-parse"] = "real" })
    H.with_patched(run_argv, "run_async_captured", rec.fn, function()
      local done = false
      local handle = git.pull_async({ dir = repo }, function()
        done = true
      end)
      H.ok(
        wait_for(function()
          return rec.parked.pull ~= nil
        end),
        label .. ": the pull itself starts"
      )
      handle.stop()
      H.ok(rec.stopped.pull, label .. ": stop() reaches the pull job")
      rec.parked.pull(unpack(shape.args))
      vim.wait(200)
      H.ok(not done, label .. ": on_done never fires after an explicit stop()")
      H.eq(
        count(rec.dispatched, "rev-parse"),
        1,
        label .. ": no after-hash read is started for a pull the caller cancelled"
      )
    end)
  end

  -- ── update_async: stop() while the fetch runs, or just as it finishes ───
  -- Without a cancelled flag the POSIX shape (a killed fetch read as a success) and a fetch
  -- that finished before the kill landed both went on to start `git pull`, which moves the
  -- working tree after the caller cancelled; the Windows shape fired on_done after stop().
  local fetch_shapes = vim.list_extend(
    vim.deepcopy(KILLED),
    { { name = "finished before the kill landed", args = { true, "", 0, "", 0 } } }
  )
  for _, shape in ipairs(fetch_shapes) do
    local label = "update_async(stopped during the fetch, " .. shape.name .. ")"
    local rec = fake_runner({})
    H.with_patched(run_argv, "run_async_captured", rec.fn, function()
      local done = false
      local handle = git.update_async({ dir = "unused" }, function()
        done = true
      end)
      H.ok(rec.parked.fetch ~= nil, label .. ": the fetch starts")
      handle.stop()
      H.ok(rec.stopped.fetch, label .. ": stop() reaches the fetch job")
      rec.parked.fetch(unpack(shape.args))
      vim.wait(200)
      H.ok(not done, label .. ": on_done never fires after an explicit stop()")
      H.eq(#rec.dispatched, 1, label .. ": the pull never starts")
    end)
  end

  -- ── update_async: stop() once the chain has reached the pull ────────────
  -- The handle is re-pointed from the fetch to the pull; stopping it there is pull_async's
  -- own cancellation, and nothing may surface afterwards.
  for _, shape in ipairs(KILLED) do
    local label = "update_async(stopped during the pull, " .. shape.name .. ")"
    local rec = fake_runner({
      fetch = { true, "", 0, "", 0 },
      ["rev-parse"] = { false, "", 128, "fatal: simulated", 0 },
    })
    H.with_patched(run_argv, "run_async_captured", rec.fn, function()
      local done = false
      local handle = git.update_async({ dir = "unused" }, function()
        done = true
      end)
      H.ok(
        wait_for(function()
          return rec.parked.pull ~= nil
        end),
        label .. ": the fetch hands off to the pull"
      )
      handle.stop()
      H.ok(rec.stopped.pull, label .. ": stop() reaches the pull job")
      rec.parked.pull(unpack(shape.args))
      vim.wait(200)
      H.ok(not done, label .. ": on_done never fires after an explicit stop()")
      H.eq(count(rec.dispatched, "rev-parse"), 1, label .. ": no after-hash read is started")
    end)
  end

  -- ── a git killed by a signal (without a stop()) is a failure ────────────
  local function reported(call)
    local res
    call(function(ok, err, changed)
      res = { ok = ok, err = err, changed = changed }
    end)
    wait_for(function()
      return res ~= nil
    end)
    return res or {}
  end

  local rec = fake_runner({ fetch = { true, "", 0, "", 15 }, push = { true, "", 0, "", 15 } })
  H.with_patched(run_argv, "run_async_captured", rec.fn, function()
    local fetch = reported(function(cb)
      git.fetch_async({ dir = "unused" }, cb)
    end)
    H.eq(fetch.ok, false, "fetch_async(killed by SIGTERM, exit code 0): a failure, not a success")
    H.ok(
      type(fetch.err) == "string" and fetch.err:find("143", 1, true),
      "fetch_async(killed by SIGTERM): the error names 128 + signal as the exit code"
    )
    H.eq(fetch.changed, nil, "fetch_async(killed by SIGTERM): no changed flag")
    local push = reported(function(cb)
      git.push_async({ dir = "unused" }, cb)
    end)
    H.eq(push.ok, false, "push_async(killed by SIGTERM, exit code 0): a failure, not a success")
    H.ok(
      type(push.err) == "string" and push.err:find("143", 1, true),
      "push_async(killed by SIGTERM): the error names 128 + signal as the exit code"
    )
  end)

  -- A pull the OOM killer ended: the before-hash read is fine, the pull is SIGKILLed. Before the
  -- fix this was a success whose `changed` was derived from a HEAD that never moved.
  local pull_killed = fake_runner({
    ["rev-parse"] = { true, "abc123\n", 0, "", 0 },
    pull = { true, "", 0, "", 9 },
  })
  H.with_patched(run_argv, "run_async_captured", pull_killed.fn, function()
    local pull = reported(function(cb)
      git.pull_async({ dir = "unused" }, cb)
    end)
    H.eq(pull.ok, false, "pull_async(killed by SIGKILL, exit code 0): a failure, not a success")
    H.ok(
      type(pull.err) == "string" and pull.err:find("137", 1, true),
      "pull_async(killed by SIGKILL): the error names 128 + signal as the exit code"
    )
    H.eq(pull.changed, nil, "pull_async(killed by SIGKILL): no changed flag")
    H.eq(count(pull_killed.dispatched, "rev-parse"), 1, "pull_async(killed): no after-hash read")
  end)

  -- ── a git that cannot be spawned reports why, not "exit code -1" ────────
  -- `run_async_captured` delivers the reason in the stdout slot, with Neovim's own source
  -- position in front.
  local spawn_failure = "vim/_core/system.lua:324: ENOENT: no such file or directory (cmd): 'git'"
  local unspawnable = fake_runner({
    fetch = { false, spawn_failure, -1, "", 0 },
    pull = { false, spawn_failure, -1, "", 0 },
    ["rev-parse"] = { false, spawn_failure, -1, "", 0 },
    push = { false, spawn_failure, -1, "", 0 },
  })
  H.with_patched(run_argv, "run_async_captured", unspawnable.fn, function()
    local calls = {
      fetch = function(cb)
        git.fetch_async({ dir = "unused" }, cb)
      end,
      pull = function(cb)
        git.pull_async({ dir = "unused" }, cb)
      end,
      push = function(cb)
        git.push_async({ dir = "unused" }, cb)
      end,
    }
    for _, name in ipairs({ "fetch", "pull", "push" }) do
      local res = reported(calls[name])
      H.eq(res.ok, false, name .. "_async(git cannot be spawned): fails")
      H.eq(
        res.err,
        "ENOENT: no such file or directory (cmd): 'git'",
        name .. "_async(git cannot be spawned): the reason, without Neovim's source position"
      )
    end
  end)

  -- A runtime that embeds its Lua sources reports the stamp without the extension
  -- (`vim/_core/system:324:`, Arch nvim 0.12.5): it is stripped all the same.
  local embedded = "vim/_core/system:324: ENOENT: no such file or directory (cmd): 'git'"
  local embedded_fake = fake_runner({ fetch = { false, embedded, -1, "", 0 } })
  H.with_patched(run_argv, "run_async_captured", embedded_fake.fn, function()
    local res = reported(function(cb)
      git.fetch_async({ dir = "unused" }, cb)
    end)
    H.eq(
      res.err,
      "ENOENT: no such file or directory (cmd): 'git'",
      "fetch_async(git cannot be spawned, stamp without .lua): the reason, without the position"
    )
  end)

  -- ── the async readers: status / show / blame ────────────────────────────
  -- They used to call `run_async_captured` directly, so a git killed by a signal (exit code 0,
  -- `signal` set, POSIX) read as a successful empty answer.
  local readers = {
    status = function(cb)
      git.status_porcelain_async({ dir = "unused" }, function(map, err)
        cb(map == nil, err, map)
      end)
    end,
    show = function(cb)
      git.show_async("HEAD", "a.txt", { dir = "unused" }, function(content, err)
        cb(content == nil, err, content)
      end)
    end,
    blame = function(cb)
      git.blame_porcelain_async("a.txt", { dir = "unused" }, function(entries, err)
        cb(entries == nil, err, entries)
      end)
    end,
  }
  for _, name in ipairs({ "status", "show", "blame" }) do
    local killed = fake_runner({ [name] = { true, "", 0, "", 15 } })
    H.with_patched(run_argv, "run_async_captured", killed.fn, function()
      local res
      readers[name](function(failed, err, value)
        res = { failed = failed, err = err, value = value }
      end)
      wait_for(function()
        return res ~= nil
      end)
      res = res or {}
      H.eq(
        res.failed,
        true,
        name .. "(killed by SIGTERM, exit code 0): a failure, not an empty result"
      )
      H.eq(res.value, nil, name .. "(killed by SIGTERM): no value")
      H.ok(type(res.err) == "string" and res.err ~= "", name .. "(killed by SIGTERM): an error")
    end)

    local nospawn = fake_runner({ [name] = { false, spawn_failure, -1, "", 0 } })
    H.with_patched(run_argv, "run_async_captured", nospawn.fn, function()
      local res
      readers[name](function(failed, err)
        res = { failed = failed, err = err }
      end)
      wait_for(function()
        return res ~= nil
      end)
      res = res or {}
      H.eq(res.failed, true, name .. "(git cannot be spawned): fails")
      H.eq(
        res.err,
        "ENOENT: no such file or directory (cmd): 'git'",
        name .. "(git cannot be spawned): the reason, without Neovim's source position"
      )
    end)
  end

  -- The same with the real runner: a `git_cmd` that does not exist.
  do
    local repo = tmpdir("-git-cancel-nogit")
    local missing = "lib-nvim-spec-no-such-git"
    for name, call in pairs({
      fetch = function(cb)
        git.fetch_async({ dir = repo }, cb, missing)
      end,
      pull = function(cb)
        git.pull_async({ dir = repo }, cb, missing)
      end,
      push = function(cb)
        git.push_async({ dir = repo }, cb, missing)
      end,
    }) do
      local res = reported(call)
      H.eq(res.ok, false, name .. "_async(real runner, git_cmd does not exist): fails")
      H.ok(
        type(res.err) == "string" and res.err:find(missing, 1, true),
        name .. "_async(real runner, git_cmd does not exist): the reason names the command"
      )
      H.ok(
        type(res.err) == "string" and not res.err:find("exit code -1", 1, true),
        name .. "_async(real runner, git_cmd does not exist): not a bare 'exit code -1'"
      )
      H.ok(
        type(res.err) == "string" and not res.err:find("^vim[/\\]"),
        name .. "_async(real runner, git_cmd does not exist): without Neovim's source position"
      )
    end
  end
end

return function(H)
  -- The first failing assertion aborts `run`; the fixtures are removed all the same, and the
  -- error reaches the runner unchanged.
  local ok, err = pcall(run, H)
  for _, dir in ipairs(created) do
    pcall(vim.fn.delete, dir, "rf")
  end
  created = {}
  if not ok then
    error(err, 0)
  end
end
