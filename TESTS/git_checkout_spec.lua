-- TESTS/git_checkout_spec.lua — lib.nvim.git.checkout
--
-- Added for GS-15 (ui.nvim's git_clickable and gitsuite.nvim's branch.switch
-- both wanted the same `git checkout <name>` wrapper). Against a real
-- fixture repo, not string mocks: the point under test is that failure
-- actually surfaces git's own stderr (`run_blocking`, unlike the
-- `run_blocking_captured`-based helpers elsewhere in this module, which only
-- ever see stdout).

return function(H)
  local git = require("lib.nvim.git")

  local created = {} ---@type string[]
  local function tmpdir(suffix)
    local dir = vim.fn.tempname() .. suffix
    vim.fn.mkdir(dir, "p")
    created[#created + 1] = dir
    return dir
  end

  ---@param dir string
  ---@param args string[]
  ---@return string stdout
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
    H.ok(res.code == 0, ("fixture: git %s failed: %s"):format(table.concat(args, " "), res.stderr))
    return vim.trim(res.stdout or "")
  end

  local repo = tmpdir("-git-checkout")
  git_run(repo, { "init", "-q", "-b", "main" })
  vim.fn.writefile({ "x" }, repo .. "/a.txt")
  git_run(repo, { "add", "-A" })
  git_run(repo, { "commit", "-q", "-m", "first" })
  git_run(repo, { "checkout", "-q", "-b", "feature" })
  git_run(repo, { "checkout", "-q", "main" })

  -- ── happy path ─────────────────────────────────────────────────────────
  local ok, err = git.checkout("feature", { dir = repo })
  H.eq(ok, true, "checkout: switching to an existing local branch succeeds")
  H.eq(err, nil, "checkout: no error on success")
  H.eq(
    git.current_branch({ dir = repo }),
    "feature",
    "checkout: HEAD actually moved to the checked-out branch"
  )

  git_run(repo, { "checkout", "-q", "main" })

  -- ── failure: unknown revision -- git's own stderr, not a generic message ──
  local bad_ok, bad_err = git.checkout("does-not-exist", { dir = repo })
  H.eq(bad_ok, false, "checkout: an unknown branch fails")
  H.ok(
    bad_err ~= nil and bad_err:find("did not match", 1, true) ~= nil,
    ("checkout: expected git's own pathspec message, got %s"):format(vim.inspect(bad_err))
  )
  H.eq(
    git.current_branch({ dir = repo }),
    "main",
    "checkout: a failed checkout leaves HEAD exactly where it was"
  )

  -- ── invalid name: rejected outright, never reaches git ────────────────────
  local dash_ok, dash_err = git.checkout("-x", { dir = repo })
  H.eq(dash_ok, false, "checkout: a name starting with '-' is refused")
  H.ok(
    dash_err ~= nil and dash_err:find("invalid revision", 1, true) ~= nil,
    ("checkout: expected the rejection message, got %s"):format(vim.inspect(dash_err))
  )
  H.eq(git.current_branch({ dir = repo }), "main", "checkout: the rejected call did not touch HEAD")

  for _, dir in ipairs(created) do
    pcall(vim.fn.delete, dir, "rf")
  end
end
