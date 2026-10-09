-- TESTS/git_sync_spec.lua — lib.nvim.git.{fetch,pull,push,update}_async
--
-- Against real local repositories with a real (bare, file-path) remote --
-- not string mocks: the point under test is that `changed` genuinely tracks
-- "did this call move a ref", parsed out of git's own stdout/stderr, and
-- that a real failure (non-fast-forward) surfaces git's real reason.

-- Module level on purpose: the cleanup at the bottom must see the directories of a run that raised.
local created = {} ---@type string[]

local function run(H)
  local git = require("lib.nvim.git")

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

  ---@param dir string
  ---@param args string[]
  ---@return string stdout, boolean ok
  local function git_run(dir, args)
    local argv = {
      "git",
      "-c",
      "user.name=lib-nvim-spec",
      "-c",
      "user.email=spec@example.invalid",
      "-c",
      "commit.gpgsign=false",
      "-C",
      dir,
    }
    vim.list_extend(argv, args)
    local res = vim.system(argv, { text = true }):wait()
    return vim.trim(res.stdout or ""), res.code == 0
  end

  -- ── fixture: a bare "remote" plus two clones of it ──────────────────────
  local bare = tmpdir("-git-sync-bare")
  local _, bare_ok = git_run(bare, { "init", "-q", "--bare", "-b", "main" })
  H.ok(bare_ok, "fixture: bare remote created")

  local a = tmpdir("-git-sync-a")
  local _, clone_a_ok = git_run(a, { "clone", "-q", bare, "." })
  H.ok(clone_a_ok, "fixture: repo a cloned from the bare remote")
  vim.fn.writefile({ "one" }, a .. "/file.txt")
  git_run(a, { "add", "-A" })
  git_run(a, { "commit", "-q", "-m", "first" })
  local _, push1_ok = git_run(a, { "push", "-q", "origin", "main" })
  H.ok(push1_ok, "fixture: repo a pushed the first commit to the bare remote")

  local b = tmpdir("-git-sync-b")
  local _, clone_b_ok = git_run(b, { "clone", "-q", bare, "." })
  H.ok(clone_b_ok, "fixture: repo b cloned from the bare remote (has the first commit)")

  -- ── fetch_async: nothing new yet ────────────────────────────────────────
  do
    local done, ok, err, changed
    git.fetch_async({ dir = b }, function(ok_, err_, changed_)
      done, ok, err, changed = true, ok_, err_, changed_
    end)
    H.ok(
      wait_for(function()
        return done
      end),
      "fetch_async: on_done fires"
    )
    H.eq(ok, true, "fetch_async: succeeds against a real remote")
    H.eq(err, nil, "fetch_async: no error on success")
    H.eq(changed, false, "fetch_async: nothing new upstream reports changed = false")
  end

  -- ── a second commit lands on the remote via repo a ──────────────────────
  vim.fn.writefile({ "two" }, a .. "/file2.txt")
  git_run(a, { "add", "-A" })
  git_run(a, { "commit", "-q", "-m", "second" })
  local _, push2_ok = git_run(a, { "push", "-q", "origin", "main" })
  H.ok(push2_ok, "fixture: repo a pushed a second commit")

  -- ── fetch_async: now there is something new ─────────────────────────────
  do
    local done, ok, err, changed
    git.fetch_async({ dir = b }, function(ok_, err_, changed_)
      done, ok, err, changed = true, ok_, err_, changed_
    end)
    H.ok(
      wait_for(function()
        return done
      end),
      "fetch_async(2): on_done fires"
    )
    H.eq(ok, true, "fetch_async(2): succeeds")
    H.eq(err, nil, "fetch_async(2): no error on success")
    H.eq(changed, true, "fetch_async(2): a moved remote-tracking ref reports changed = true")
  end

  -- ── pull_async: fast-forwards onto the fetched commit ───────────────────
  do
    local done, ok, err, changed
    git.pull_async({ dir = b }, function(ok_, err_, changed_)
      done, ok, err, changed = true, ok_, err_, changed_
    end)
    H.ok(
      wait_for(function()
        return done
      end),
      "pull_async: on_done fires"
    )
    H.eq(ok, true, "pull_async: fast-forward succeeds")
    H.eq(err, nil, "pull_async: no error on success")
    H.eq(changed, true, "pull_async: an actual fast-forward reports changed = true")
    H.ok(
      vim.uv.fs_stat(b .. "/file2.txt") ~= nil,
      "pull_async: the working tree actually moved forward"
    )
  end

  -- ── pull_async: nothing left to merge ────────────────────────────────────
  do
    local done, ok, err, changed
    git.pull_async({ dir = b }, function(ok_, err_, changed_)
      done, ok, err, changed = true, ok_, err_, changed_
    end)
    H.ok(
      wait_for(function()
        return done
      end),
      "pull_async(again): on_done fires"
    )
    H.eq(ok, true, "pull_async(again): still succeeds")
    H.eq(err, nil, "pull_async(again): no error on success")
    H.eq(changed, false, "pull_async(again): already up to date reports changed = false")
  end

  -- ── push_async: repo b pushes a commit of its own ───────────────────────
  do
    vim.fn.writefile({ "from b" }, b .. "/file3.txt")
    git_run(b, { "add", "-A" })
    git_run(b, { "commit", "-q", "-m", "third, from b" })

    local done, ok, err
    git.push_async({ dir = b }, function(ok_, err_)
      done, ok, err = true, ok_, err_
    end)
    H.ok(
      wait_for(function()
        return done
      end),
      "push_async: on_done fires"
    )
    H.eq(ok, true, "push_async: succeeds against a real remote")
    H.eq(err, nil, "push_async: no error on success")

    local log, log_ok = git_run(bare, { "log", "-1", "--format=%s", "main" })
    H.ok(log_ok, "push_async: the bare remote's main can be read back")
    H.eq(log, "third, from b", "push_async: the bare remote actually received the new commit")
  end

  -- ── push_async: rejected (repo a is now behind, diverged) ───────────────
  do
    vim.fn.writefile({ "conflicting" }, a .. "/file4.txt")
    git_run(a, { "add", "-A" })
    git_run(a, { "commit", "-q", "-m", "fourth, from a, diverged" })

    local done, ok, err
    git.push_async({ dir = a }, function(ok_, err_)
      done, ok, err = true, ok_, err_
    end)
    H.ok(
      wait_for(function()
        return done
      end),
      "push_async(rejected): on_done fires"
    )
    H.eq(ok, false, "push_async(rejected): a non-fast-forward push fails")
    H.ok(
      type(err) == "string" and #err > 0,
      "push_async(rejected): reports git's own rejection reason"
    )
  end

  -- ── pull_async: rejected (repo a's local branch has diverged history) ───
  do
    local done, ok, err, changed
    git.pull_async({ dir = a }, function(ok_, err_, changed_)
      done, ok, err, changed = true, ok_, err_, changed_
    end)
    H.ok(
      wait_for(function()
        return done
      end),
      "pull_async(rejected): on_done fires"
    )
    H.eq(ok, false, "pull_async(rejected): a diverged history cannot fast-forward")
    H.ok(
      type(err) == "string" and #err > 0,
      "pull_async(rejected): reports git's own diagnostic, not a bare nil"
    )
    H.eq(changed, nil, "pull_async(rejected): no changed flag on failure")
  end

  -- ── fetch_async: failure surfaces a real error, not a silent nil ────────
  do
    local not_repo = tmpdir("-git-sync-not-a-repo")
    local done, ok, err
    git.fetch_async({ dir = not_repo }, function(ok_, err_)
      done, ok, err = true, ok_, err_
    end)
    H.ok(
      wait_for(function()
        return done
      end),
      "fetch_async(not a repo): on_done fires"
    )
    H.eq(ok, false, "fetch_async(not a repo): fails")
    H.ok(type(err) == "string" and #err > 0, "fetch_async(not a repo): reports why")
  end

  -- ── update_async: fetch + fast-forward pull, combined ───────────────────
  do
    -- A third commit on the remote, via a fresh clone (a/b's histories are
    -- diverged messes by this point in the fixture).
    local c = tmpdir("-git-sync-c")
    git_run(c, { "clone", "-q", bare, "." })
    vim.fn.writefile({ "fifth" }, c .. "/file5.txt")
    git_run(c, { "add", "-A" })
    git_run(c, { "commit", "-q", "-m", "fifth" })
    git_run(c, { "push", "-q", "-f", "origin", "main" })

    -- b's local main still points at its own (now-rejected) history, but
    -- update_async only needs its remote-tracking ref to move, then
    -- fast-forward its own main *if* main itself is exactly behind (it must
    -- be reset to track the bare remote's rewritten history first, same as
    -- a real "someone force-pushed, catch up" scenario would after a manual
    -- `git reset --hard origin/main`).
    git_run(b, { "reset", "-q", "--hard", "origin/main" })

    local done, ok, err, changed
    git.update_async({ dir = b }, function(ok_, err_, changed_)
      done, ok, err, changed = true, ok_, err_, changed_
    end)
    H.ok(
      wait_for(function()
        return done
      end),
      "update_async: on_done fires"
    )
    H.eq(ok, true, "update_async: fetch + pull succeeds")
    H.eq(err, nil, "update_async: no error on success")
    H.eq(changed, true, "update_async: the pull half's changed flag comes through")
    H.ok(
      vim.uv.fs_stat(b .. "/file5.txt") ~= nil,
      "update_async: the working tree actually moved forward"
    )
  end

  -- ── update_async: a failing fetch short-circuits before any pull ────────
  do
    local not_repo = tmpdir("-git-sync-not-a-repo-2")
    local done, ok, err, changed
    git.update_async({ dir = not_repo }, function(ok_, err_, changed_)
      done, ok, err, changed = true, ok_, err_, changed_
    end)
    H.ok(
      wait_for(function()
        return done
      end),
      "update_async(fetch fails): on_done fires"
    )
    H.eq(ok, false, "update_async(fetch fails): reports the fetch's own failure")
    H.ok(type(err) == "string" and #err > 0, "update_async(fetch fails): reports why")
    H.eq(changed, nil, "update_async(fetch fails): no changed flag when the fetch never got there")
  end

  -- ── update_async: the returned handle re-points from fetch to pull ──────
  -- Regression for a bug where update_async always returned fetch_async's
  -- own handle, so calling .stop() once the pull had started silently
  -- killed an already-finished fetch job and left the real, in-flight
  -- `git pull` completely untracked. `pull_async` is monkey-patched
  -- (through the same module table `update_async` itself calls via `M.`)
  -- so this is deterministic rather than racing real process timing.
  do
    local repo = tmpdir("-git-sync-update-handle")
    git_run(repo, { "init", "-q", "-b", "main" })

    local pull_stop_called = false
    local pull_started = false
    local fake_pull_async = function()
      pull_started = true
      return {
        stop = function()
          pull_stop_called = true
        end,
      }
    end

    H.with_patched(git, "pull_async", fake_pull_async, function()
      local ok_call, handle = pcall(git.update_async, { dir = repo }, function() end)
      H.ok(ok_call, "update_async: does not raise with pull_async faked")

      H.ok(
        wait_for(function()
          return handle.stop ~= nil
        end),
        "update_async: returns a handle immediately"
      )

      -- The repo has no remotes, so `git fetch --all --prune` resolves with nothing to do and
      -- update_async's own fetch callback calls the (faked) pull_async right after. Waiting
      -- for that call rather than a fixed 300 ms: on a loaded machine the fetch takes longer,
      -- and stop() would still reach the fetch job.
      H.ok(
        wait_for(function()
          return pull_started
        end),
        "update_async: the fetch hands off to the pull"
      )

      handle.stop()
      H.ok(
        pull_stop_called,
        "update_async: handle.stop() reaches the pull job, not the (finished) fetch job"
      )
    end)
  end

  -- ── pull_async: a HEAD read that fails on its own (not cancelled) still ──
  -- lets the real pull run ──────────────────────────────────────────────────
  -- `git rev-parse HEAD` exits non-zero for a genuinely empty repository
  -- (no commits yet -- verified directly: an entirely normal state to run
  -- `pull_async` against) exactly the same way it does for a killed
  -- process, so pull_async must NOT treat "the HEAD read failed" as
  -- grounds to abort the pull -- only an explicit stop() should. This is
  -- the regression an earlier version of this fix introduced (it gated on
  -- head_hash_async's `ok` instead of tracking cancellation separately).
  do
    local run_argv = require("lib.nvim.cross.run_argv")
    local original_run_async_captured = run_argv.run_async_captured
    local bare1 = tmpdir("-git-sync-before-hash-fails-bare")
    git_run(bare1, { "init", "-q", "--bare", "-b", "main" })
    local src = tmpdir("-git-sync-before-hash-fails-src")
    git_run(src, { "clone", "-q", bare1, "." })
    vim.fn.writefile({ "x" }, src .. "/f.txt")
    git_run(src, { "add", "-A" })
    git_run(src, { "commit", "-q", "-m", "first" })
    git_run(src, { "push", "-q", "origin", "main" })
    local repo = tmpdir("-git-sync-before-hash-fails-repo")
    git_run(repo, { "clone", "-q", bare1, "." })

    local pull_was_dispatched = false
    local fake_run_async_captured = function(argv, on_done, ...)
      if vim.tbl_contains(argv, "pull") then
        pull_was_dispatched = true
      end
      if vim.tbl_contains(argv, "rev-parse") then
        vim.schedule(function()
          on_done(false, "", 128, "fatal: simulated failure")
        end)
        return { stop = function() end }
      end
      return original_run_async_captured(argv, on_done, ...)
    end

    H.with_patched(run_argv, "run_async_captured", fake_run_async_captured, function()
      local done, ok
      git.pull_async({ dir = repo }, function(ok_)
        done, ok = true, ok_
      end)
      H.ok(
        wait_for(function()
          return done
        end),
        "pull_async(before-hash fails, not cancelled): on_done fires"
      )
      H.eq(
        ok,
        true,
        "pull_async(before-hash fails, not cancelled): still runs the real pull -- a failed HEAD read on its own is not cancellation"
      )
      H.ok(
        pull_was_dispatched,
        "pull_async(before-hash fails, not cancelled): the real `git pull` must still be dispatched"
      )
    end)
  end

  -- ── pull_async: stop() during the before-hash read prevents the real ────
  -- pull from ever starting ─────────────────────────────────────────────────
  -- The before-hash read is intercepted and its on_done deliberately
  -- withheld until after handle.stop() has been called, then fired --
  -- mirroring run_async_captured's own real behavior, where killing a job
  -- via stop() still lets its on_done fire once, reporting the kill as an
  -- ordinary failure (verified directly against the real implementation).
  do
    local run_argv = require("lib.nvim.cross.run_argv")
    local original_run_async_captured = run_argv.run_async_captured
    local repo = tmpdir("-git-sync-stop-before-hash")
    git_run(repo, { "init", "-q", "-b", "main" })

    local pull_was_dispatched = false
    local captured_on_done
    local fake_run_async_captured = function(argv, on_done, ...)
      if vim.tbl_contains(argv, "pull") then
        pull_was_dispatched = true
      end
      if vim.tbl_contains(argv, "rev-parse") and not captured_on_done then
        captured_on_done = on_done
        return { stop = function() end }
      end
      return original_run_async_captured(argv, on_done, ...)
    end

    H.with_patched(run_argv, "run_async_captured", fake_run_async_captured, function()
      local done
      local handle = git.pull_async({ dir = repo }, function()
        done = true
      end)

      H.ok(
        wait_for(function()
          return captured_on_done ~= nil
        end),
        "pull_async: the before-hash read actually starts"
      )

      handle.stop()
      captured_on_done(false, "", 143, "")
      vim.wait(300)

      H.ok(
        not done,
        "pull_async(stopped during before-hash): on_done never fires after an explicit stop()"
      )
      H.ok(
        not pull_was_dispatched,
        "pull_async(stopped during before-hash): the real `git pull` must never be dispatched"
      )
    end)
  end

  -- ── pull_async: stop() during the after-hash read never reports a ───────
  -- result -- not even a guessed changed value ─────────────────────────────
  do
    local run_argv = require("lib.nvim.cross.run_argv")
    local original_run_async_captured = run_argv.run_async_captured
    local bare2 = tmpdir("-git-sync-stop-after-hash-bare")
    git_run(bare2, { "init", "-q", "--bare", "-b", "main" })
    local src = tmpdir("-git-sync-stop-after-hash-src")
    git_run(src, { "clone", "-q", bare2, "." })
    vim.fn.writefile({ "x" }, src .. "/f.txt")
    git_run(src, { "add", "-A" })
    git_run(src, { "commit", "-q", "-m", "first" })
    git_run(src, { "push", "-q", "origin", "main" })
    local repo = tmpdir("-git-sync-stop-after-hash-repo")
    git_run(repo, { "clone", "-q", bare2, "." })
    vim.fn.writefile({ "y" }, src .. "/f2.txt")
    git_run(src, { "add", "-A" })
    git_run(src, { "commit", "-q", "-m", "second" })
    git_run(src, { "push", "-q", "origin", "main" })
    git_run(repo, { "fetch", "-q" })

    local rev_parse_count = 0
    local captured_on_done
    local fake_run_async_captured = function(argv, on_done, ...)
      if vim.tbl_contains(argv, "rev-parse") then
        rev_parse_count = rev_parse_count + 1
        if rev_parse_count > 1 then
          captured_on_done = on_done
          return { stop = function() end }
        end
      end
      return original_run_async_captured(argv, on_done, ...)
    end

    H.with_patched(run_argv, "run_async_captured", fake_run_async_captured, function()
      local done
      local handle = git.pull_async({ dir = repo }, function()
        done = true
      end)

      H.ok(
        wait_for(function()
          return captured_on_done ~= nil
        end),
        "pull_async: reaches the after-hash read once the pull itself has completed"
      )

      handle.stop()
      captured_on_done(false, "", 143, "")
      vim.wait(300)

      H.ok(
        not done,
        "pull_async(stopped during after-hash): on_done never fires after an explicit stop(), not even a guessed changed value"
      )
    end)
  end

  -- ── pull_async: an after-hash read that fails for a reason OTHER than ───
  -- cancellation reports changed = nil, never a guessed true/false ────────
  -- Regression: a HEAD-hash read failing (nil) was, for a while, treated
  -- identically at both the before- and after-hash stages. That is right
  -- for the before read (a genuinely empty repo fails the same way), but
  -- wrong for the after read: a `git pull --ff-only` that exits 0 (this
  -- fixture's pull genuinely succeeds) proves the upstream ref already had
  -- commits -- an empty upstream makes the pull itself fail rather than
  -- silently no-op (verified directly) -- so a failed after-read here can
  -- only be a genuine, unrelated error, and comparing a real `before` hash
  -- against `nil` would otherwise silently report a guessed `changed`.
  do
    local run_argv = require("lib.nvim.cross.run_argv")
    local original_run_async_captured = run_argv.run_async_captured
    local bare3 = tmpdir("-git-sync-after-hash-fails-bare")
    git_run(bare3, { "init", "-q", "--bare", "-b", "main" })
    local src = tmpdir("-git-sync-after-hash-fails-src")
    git_run(src, { "clone", "-q", bare3, "." })
    vim.fn.writefile({ "x" }, src .. "/f.txt")
    git_run(src, { "add", "-A" })
    git_run(src, { "commit", "-q", "-m", "first" })
    git_run(src, { "push", "-q", "origin", "main" })
    local repo = tmpdir("-git-sync-after-hash-fails-repo")
    git_run(repo, { "clone", "-q", bare3, "." })
    vim.fn.writefile({ "y" }, src .. "/f2.txt")
    git_run(src, { "add", "-A" })
    git_run(src, { "commit", "-q", "-m", "second" })
    git_run(src, { "push", "-q", "origin", "main" })
    git_run(repo, { "fetch", "-q" })

    local rev_parse_count = 0
    local fake_run_async_captured = function(argv, on_done, ...)
      if vim.tbl_contains(argv, "rev-parse") then
        rev_parse_count = rev_parse_count + 1
        if rev_parse_count > 1 then
          vim.schedule(function()
            on_done(false, "", 1, "fatal: simulated unrelated failure")
          end)
          return { stop = function() end }
        end
      end
      return original_run_async_captured(argv, on_done, ...)
    end

    H.with_patched(run_argv, "run_async_captured", fake_run_async_captured, function()
      local done, ok, err, changed
      git.pull_async({ dir = repo }, function(ok_, err_, changed_)
        done, ok, err, changed = true, ok_, err_, changed_
      end)
      H.ok(
        wait_for(function()
          return done
        end),
        "pull_async(after-hash fails, not cancelled): on_done fires"
      )
      H.eq(ok, true, "pull_async(after-hash fails, not cancelled): the pull itself still succeeded")
      H.eq(err, nil, "pull_async(after-hash fails, not cancelled): no error on a successful pull")
      H.eq(
        changed,
        nil,
        "pull_async(after-hash fails, not cancelled): changed stays honestly unknown, not a guessed true/false"
      )
    end)
  end

  -- ── network verbs: no interactive prompt, a deadline ─────────────────────
  -- Neovim cannot answer a prompt git raises itself, so fetch/pull/push run with
  -- GIT_TERMINAL_PROMPT=0 and a 120 s deadline unless the caller says otherwise.
  -- pull_async and update_async start two more git processes around the pull -- the
  -- `rev-parse HEAD` reads that decide `changed` -- and those get the very same
  -- environment and deadline as the pull (6943abd): otherwise a `GIT_DIR` in
  -- `opts.env` would send the before/after comparison to another repository, and a
  -- hung read would outlast the deadline of the pull it brackets. The HEAD reads
  -- run for real here; their runner options are recorded and compared.
  do
    local run_argv = require("lib.nvim.cross.run_argv")
    local original = run_argv.run_async_captured
    local repo = tmpdir("-git-sync-net-opts")
    git_run(repo, { "init", "-q", "-b", "main" })
    -- One commit, so the HEAD reads of pull_async/update_async succeed; the faked
    -- pull moves nothing, so `changed` must come out false.
    vim.fn.writefile({ "x" }, repo .. "/f.txt")
    git_run(repo, { "add", "-A" })
    git_run(repo, { "commit", "-q", "-m", "first" })

    --- One git process the verb under test started, in the order it was started.
    ---@class Spec.GitSync.Process
    ---@field step string "fetch", "pull", "push", or "head" (a `rev-parse HEAD` read around a pull)
    ---@field argv string[] The complete argv.
    ---@field ropts table|nil The runner options it was started with; nil when none were passed.
    ---@field input string|nil The standard input it was started with; nil when none was passed.

    --- Which step of a verb an argv is.
    ---@param argv string[]
    ---@return string step "head" for the `rev-parse HEAD` reads, else the git verb ("other" if unknown).
    local function step_of(argv)
      if vim.tbl_contains(argv, "rev-parse") then
        return "head"
      end
      for _, verb in ipairs({ "fetch", "pull", "push" }) do
        if vim.tbl_contains(argv, verb) then
          return verb
        end
      end
      return "other"
    end

    --- Run `verb` with a fake runner: the network steps are answered by `reply`, the
    --- `rev-parse HEAD` reads run for real, and every process started is recorded.
    ---@param verb string "fetch", "pull", "push" or "update"
    ---@param opts table
    ---@param reply fun(ropts: table|nil, step: string): boolean, string, integer, string, integer What the process reports: the arguments of its `on_done`.
    ---@return table|nil seen The runner options of the last network step (not a HEAD read).
    ---@return { ok: boolean, err: string|nil, changed: boolean|nil } result What the verb reported.
    ---@return Spec.GitSync.Process[] trace Every process the verb started, in order.
    local function drive(verb, opts, reply)
      local seen, result
      local trace = {} ---@type Spec.GitSync.Process[]
      local fake = function(argv, on_done, input, ropts)
        local step = step_of(argv)
        trace[#trace + 1] = { step = step, argv = argv, ropts = ropts, input = input }
        if step == "head" then
          return original(argv, on_done, input, ropts)
        end
        seen = ropts
        vim.schedule(function()
          on_done(reply(ropts, step))
        end)
        return { stop = function() end }
      end
      H.with_patched(run_argv, "run_async_captured", fake, function()
        opts.dir = repo
        git[verb .. "_async"](opts, function(ok, err, changed)
          result = { ok = ok, err = err, changed = changed }
        end)
        wait_for(function()
          return result ~= nil
        end)
        H.ok(result ~= nil, verb .. "_async: on_done fires")
      end)
      return seen, result, trace
    end

    local function fine()
      return true, "", 0, "", 0
    end

    --- The process reports that git was killed for its deadline (exit code 124 plus the signal).
    local function timed_out()
      return false, "", 124, "", 15
    end

    --- The steps of a trace as one string, e.g. "head pull head".
    ---@param trace Spec.GitSync.Process[]
    ---@return string
    local function steps_of(trace)
      local names = {} ---@type string[]
      for i, proc in ipairs(trace) do
        names[i] = proc.step
      end
      return table.concat(names, " ")
    end

    --- The directory a recorded git process ran against (`git -C <dir>`).
    ---@param argv string[]
    ---@return string|nil
    local function dir_of(argv)
      for i, arg in ipairs(argv) do
        if arg == "-C" then
          return argv[i + 1]
        end
      end
      return nil
    end

    --- Assert that one recorded process was started for the caller's options: in `repo`,
    --- with exactly the environment `env` and the deadline `ms` (nil: none).
    ---@param label string
    ---@param proc Spec.GitSync.Process
    ---@param env table<string, string>
    ---@param ms integer|nil
    local function check_process(label, proc, env, ms)
      H.eq(dir_of(proc.argv), repo, label .. ": runs against opts.dir")
      H.ok(proc.ropts ~= nil, label .. ": is started with the network runner options")
      H.ok(
        vim.deep_equal(proc.ropts.env, env),
        ("%s: environment is %s, expected %s"):format(
          label,
          vim.inspect(proc.ropts.env),
          vim.inspect(env)
        )
      )
      H.eq(proc.ropts.timeout_ms, ms, label .. ": deadline")
    end

    for _, verb in ipairs({ "fetch", "pull", "push" }) do
      local seen = drive(verb, {}, fine)
      H.eq(seen.env.GIT_TERMINAL_PROMPT, "0", verb .. "_async: GIT_TERMINAL_PROMPT=0 by default")
      H.eq(seen.timeout_ms, 120000, verb .. "_async: 120 s deadline by default")

      seen =
        drive(verb, { env = { GIT_TERMINAL_PROMPT = "1", GIT_X = "y" }, timeout_ms = 5000 }, fine)
      H.eq(seen.env.GIT_TERMINAL_PROMPT, "1", verb .. "_async: opts.env wins over the default")
      H.eq(seen.env.GIT_X, "y", verb .. "_async: opts.env is passed through")
      H.eq(seen.timeout_ms, 5000, verb .. "_async: opts.timeout_ms replaces the deadline")

      seen = drive(verb, { timeout_ms = false }, fine)
      H.eq(seen.timeout_ms, nil, verb .. "_async: timeout_ms = false waits forever")

      local _, res = drive(verb, { timeout_ms = 3000 }, function()
        return false, "", 124, "", 15
      end)
      H.eq(res.ok, false, verb .. "_async: a timeout is a failure")
      H.eq(
        res.err,
        ("git %s timed out after 3s"):format(verb),
        verb .. "_async: the error names the deadline"
      )
    end

    -- ── every process of pull_async/update_async: one environment, one deadline ──
    -- What the caller passes, and the environment and deadline every process of the
    -- call must then have. `ms = nil` is "no deadline" (a nil field is simply absent).
    local SCENARIOS = {
      {
        name = "defaults",
        opts = {},
        env = { GIT_TERMINAL_PROMPT = "0" },
        ms = 120000,
      },
      {
        name = "caller env merged over the default",
        opts = { env = { GIT_X = "y" } },
        env = { GIT_TERMINAL_PROMPT = "0", GIT_X = "y" },
        ms = 120000,
      },
      {
        name = "caller env and deadline win",
        opts = { env = { GIT_TERMINAL_PROMPT = "1", GIT_X = "y" }, timeout_ms = 5000 },
        env = { GIT_TERMINAL_PROMPT = "1", GIT_X = "y" },
        ms = 5000,
      },
      {
        name = "timeout_ms = false",
        opts = { timeout_ms = false },
        env = { GIT_TERMINAL_PROMPT = "0" },
        ms = nil,
      },
    }

    -- The processes each verb starts, in order: pull_async reads HEAD, pulls, reads HEAD
    -- again; update_async fetches first and then does all of that with the same opts.
    local CHAINS = { pull = "head pull head", update = "fetch head pull head" }

    for _, verb in ipairs({ "pull", "update" }) do
      for _, scenario in ipairs(SCENARIOS) do
        local label = ("%s_async(%s)"):format(verb, scenario.name)
        local _, res, trace = drive(verb, vim.deepcopy(scenario.opts), fine)
        H.eq(res.ok, true, label .. ": succeeds")
        H.eq(res.changed, false, label .. ": nothing moved, and both HEAD reads came back")
        H.eq(steps_of(trace), CHAINS[verb], label .. ": the processes it starts, in order")
        for i, proc in ipairs(trace) do
          check_process(
            ("%s: process %d (%s)"):format(label, i, proc.step),
            proc,
            scenario.env,
            scenario.ms
          )
        end
      end
    end

    -- ── the other Lib.Git.RunOpts fields: only no_lazy_fetch reaches the verbs ──
    -- The docs (Lib.Git.NetOpts, README, docs/API) say the verbs use dir, env and timeout_ms,
    -- honour no_lazy_fetch as `-c protocol.allow=never` (which blocks every transport, so a
    -- verb that needs the network fails under it) and ignore max_output_bytes, read_only, input
    -- and binary. Every process of every verb is checked, the HEAD reads included.
    for _, verb in ipairs({ "fetch", "pull", "push", "update" }) do
      local label = verb .. "_async(no_lazy_fetch, read_only, max_output_bytes, input, binary)"
      local _, res, trace = drive(verb, {
        no_lazy_fetch = true,
        read_only = true,
        max_output_bytes = 5,
        input = "ignored",
        binary = true,
      }, fine)
      H.eq(res.ok, true, label .. ": succeeds")
      H.ok(#trace > 0, label .. ": starts at least one process")
      for i, proc in ipairs(trace) do
        local plabel = ("%s: process %d (%s)"):format(label, i, proc.step)
        H.ok(
          vim.deep_equal(
            vim.list_slice(proc.argv, 1, 5),
            { "git", "-c", "protocol.allow=never", "-C", repo }
          ),
          plabel
            .. ": argv starts with the protocol switch, then -C <dir>, got "
            .. vim.inspect(proc.argv)
        )
        H.ok(
          not vim.tbl_contains(proc.argv, "--no-optional-locks"),
          plabel .. ": read_only is ignored"
        )
        H.eq(proc.input, nil, plabel .. ": input is ignored")
        -- the runner gets the environment and the deadline and nothing else: no output cap, no input
        local keys = vim.tbl_keys(proc.ropts)
        table.sort(keys)
        H.ok(
          vim.deep_equal(keys, { "env", "timeout_ms" }),
          plabel .. ": runner options are env and timeout_ms only, got " .. vim.inspect(keys)
        )
      end
    end

    -- ── the error text of a deadline: whole seconds, fractions, milliseconds ────
    -- Below one second whole seconds would print "0s", so those are milliseconds;
    -- from one second on the seconds are printed as the number they are.
    local DEADLINES = {
      { ms = 500, text = "500 ms" },
      { ms = 999, text = "999 ms" },
      { ms = 1000, text = "1s" },
      { ms = 1500, text = "1.5s" },
      { ms = 3000, text = "3s" },
    }

    for _, verb in ipairs({ "fetch", "pull", "push" }) do
      for _, case in ipairs(DEADLINES) do
        local label = ("%s_async(timeout_ms = %d)"):format(verb, case.ms)
        local _, res = drive(verb, { timeout_ms = case.ms }, timed_out)
        H.eq(res.ok, false, label .. ": a timeout is a failure")
        H.eq(
          res.err,
          ("git %s timed out after %s"):format(verb, case.text),
          label .. ": the error names the deadline"
        )
      end

      local _, res = drive(verb, {}, timed_out)
      H.eq(
        res.err,
        ("git %s timed out after 120s"):format(verb),
        verb .. "_async: the default deadline is the one named"
      )

      -- Progress text a killed git left on stderr does not hide the deadline ...
      _, res = drive(verb, { timeout_ms = 1500 }, function()
        return false, "", 124, "remote: Counting objects", 15
      end)
      H.eq(
        res.err,
        ("git %s timed out after 1.5s"):format(verb),
        verb .. "_async: the deadline wins over the stderr of the killed git"
      )

      -- ... and a timeout is only what the runner flagged as one: a git that exits 124 by
      -- itself (no signal), and any 124 when no deadline was set, are plain exit codes.
      _, res = drive(verb, { timeout_ms = 1500 }, function()
        return false, "", 124, "", 0
      end)
      H.eq(
        res.err,
        ("git %s failed (exit code 124)"):format(verb),
        verb .. "_async: exit code 124 without a kill is not a timeout"
      )
      _, res = drive(verb, { timeout_ms = false }, timed_out)
      H.eq(
        res.err,
        ("git %s failed (exit code 124)"):format(verb),
        verb .. "_async: without a deadline nothing is a timeout"
      )
    end

    -- pull_async: a pull that timed out ends the call without a second HEAD read
    local _, pull_res, pull_trace = drive("pull", { timeout_ms = 500 }, timed_out)
    H.eq(pull_res.err, "git pull timed out after 500 ms", "pull_async(timeout): names the deadline")
    H.eq(steps_of(pull_trace), "head pull", "pull_async(timeout): no HEAD read after the pull")

    -- update_async: the fetch and the pull each carry the caller's deadline, and the
    -- one that hits it is named; a fetch that timed out ends the call before the pull
    for _, case in ipairs(DEADLINES) do
      local label = ("update_async(timeout_ms = %d)"):format(case.ms)
      local _, res, trace = drive("update", { timeout_ms = case.ms }, timed_out)
      H.eq(res.ok, false, label .. ": a fetch timeout is a failure")
      H.eq(
        res.err,
        ("git fetch timed out after %s"):format(case.text),
        label .. ": the fetch names the deadline"
      )
      H.eq(steps_of(trace), "fetch", label .. ": the pull does not start after a fetch timeout")

      _, res, trace = drive("update", { timeout_ms = case.ms }, function(_, step)
        if step == "pull" then
          return timed_out()
        end
        return fine()
      end)
      H.eq(res.ok, false, label .. ": a pull timeout is a failure")
      H.eq(
        res.err,
        ("git pull timed out after %s"):format(case.text),
        label .. ": the pull names the deadline"
      )
      H.eq(steps_of(trace), "fetch head pull", label .. ": no HEAD read after the pull timed out")
    end
  end

  -- ── pull_async: the HEAD reads around the pull share env and deadline ─────
  -- A GIT_DIR in opts.env must reach the two `rev-parse HEAD` reads too, or `changed`
  -- compares another repository than the pull moves; a before read that hit the
  -- deadline is "unknown", not "no hash".
  do
    local run_argv = require("lib.nvim.cross.run_argv")
    local repo = tmpdir("-git-sync-head-reads")
    git_run(repo, { "init", "-q", "-b", "main" })

    --- Every git call answers at once: rev-parse HEAD with `hashes[n]` (or a deadline kill
    --- when it is `false`), anything else with success. Returns the runner options seen.
    ---@param hashes (string|false)[]
    ---@param opts table
    ---@return table[] seen, boolean|nil changed
    local function pull_with(hashes, opts)
      local seen, changed, done, reads, pull_ok, pull_err = {}, nil, false, 0, nil, nil
      local fake = function(argv, on_done, _, ropts)
        local verb = vim.tbl_contains(argv, "rev-parse") and "rev-parse" or "pull"
        seen[#seen + 1] = { verb = verb, ropts = ropts }
        vim.schedule(function()
          if verb == "rev-parse" then
            reads = reads + 1
            local hash = hashes[reads]
            if hash == false then
              on_done(false, "", 124, "", 15)
            elseif hash == "killed" then
              on_done(false, "", 0, "", 9) -- killed from outside (OOM): no deadline involved
            elseif hash == "empty" then
              on_done(false, "", 128, "fatal: ambiguous argument 'HEAD'", 0) -- git's own answer
            else
              on_done(true, hash .. "\n", 0, "", 0)
            end
          else
            on_done(true, "", 0, "", 0)
          end
        end)
        return { stop = function() end }
      end
      H.with_patched(run_argv, "run_async_captured", fake, function()
        opts.dir = repo
        git.pull_async(opts, function(ok_, err_, c)
          pull_ok, pull_err, changed, done = ok_, err_, c, true
        end)
        wait_for(function()
          return done
        end)
      end)
      H.ok(done, "pull_async: on_done fires")
      H.eq(pull_ok, true, "pull_async: the pull succeeded")
      H.eq(pull_err, nil, "pull_async: no error on success")
      return seen, changed
    end

    local seen, changed = pull_with(
      { "aaa", "aaa" },
      { env = { GIT_DIR = "x" }, timeout_ms = 5000 }
    )
    H.eq(#seen, 3, "pull_async: HEAD before, pull, HEAD after")
    for n, call in ipairs(seen) do
      H.eq(call.ropts.env.GIT_DIR, "x", "pull_async: process " .. n .. " gets opts.env")
      H.eq(
        call.ropts.env.GIT_TERMINAL_PROMPT,
        "0",
        "pull_async: process " .. n .. " gets the prompt guard"
      )
      H.eq(call.ropts.timeout_ms, 5000, "pull_async: process " .. n .. " gets the deadline")
    end
    H.eq(changed, false, "pull_async: the same HEAD before and after is no change")

    _, changed = pull_with({ "aaa", "bbb" }, {})
    H.eq(changed, true, "pull_async: a different HEAD after is a change")

    seen, changed = pull_with({ false, "aaa" }, {})
    H.eq(
      changed,
      nil,
      "pull_async: a HEAD-before read that hit the deadline leaves changed unknown"
    )
    H.eq(#seen, 2, "pull_async: ... and the HEAD-after read, which cannot change that, is not run")

    seen, changed = pull_with({ "killed", "aaa" }, {})
    H.eq(changed, nil, "pull_async: a HEAD-before read killed by a signal leaves changed unknown")
    H.eq(#seen, 2, "pull_async: ... and the HEAD-after read is not run either")

    _, changed = pull_with({ "empty", "aaa" }, {})
    H.eq(
      changed,
      true,
      "pull_async: an empty repository (git exit 128) gaining a commit is a change"
    )

    -- sub-second and fractional deadlines read naturally in the error
    for _, case in ipairs({ { 500, "500 ms" }, { 1500, "1.5s" } }) do
      local result
      H.with_patched(run_argv, "run_async_captured", function(_, on_done)
        vim.schedule(function()
          on_done(false, "", 124, "", 15)
        end)
        return { stop = function() end }
      end, function()
        git.push_async({ dir = repo, timeout_ms = case[1] }, function(_, err)
          result = err
        end)
        wait_for(function()
          return result ~= nil
        end)
      end)
      H.eq(
        result,
        "git push timed out after " .. case[2],
        "push_async: a " .. case[1] .. " ms deadline reads as " .. case[2]
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
