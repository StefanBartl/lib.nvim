-- TESTS/git_sync_spec.lua — lib.nvim.git.{fetch,pull,push,update}_async
--
-- Against real local repositories with a real (bare, file-path) remote --
-- not string mocks: the point under test is that `changed` genuinely tracks
-- "did this call move a ref", parsed out of git's own stdout/stderr, and
-- that a real failure (non-fast-forward) surfaces git's real reason.

return function(H)
  local git = require("lib.nvim.git")

  local created = {} ---@type string[]
  local function tmpdir(suffix)
    local dir = vim.fn.tempname() .. suffix
    vim.fn.mkdir(dir, "p")
    created[#created + 1] = dir
    return dir
  end

  local function wait_for(pred)
    vim.wait(10000, pred, 10)
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

  for _, dir in ipairs(created) do
    pcall(vim.fn.delete, dir, "rf")
  end
end
