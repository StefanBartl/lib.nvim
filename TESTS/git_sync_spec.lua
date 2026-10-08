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
