-- TESTS/git_hash_describe_spec.lua — lib.nvim.git: `head_hash`, `describe`.
--
-- Added alongside GS-14's buffer-ctx.nvim swap: `head_short_hash` had no
-- full-hash sibling, and `describe` (git describe --tags --always) existed
-- only baked into `M.info`'s three-process snapshot -- no standalone form for
-- a caller that wants just the one value. Both against a real fixture repo,
-- not string mocks: the point is proving the actual argv, not a parser.

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

  local repo = tmpdir("-git-hash-describe")
  git_run(repo, { "init", "-q", "-b", "main" })
  vim.fn.writefile({ "x" }, repo .. "/a.txt")
  git_run(repo, { "add", "-A" })
  git_run(repo, { "commit", "-q", "-m", "first" })

  local full = git_run(repo, { "rev-parse", "HEAD" })
  local short = git_run(repo, { "rev-parse", "--short", "HEAD" })

  H.eq(git.head_hash({ dir = repo }), full, "head_hash({dir}): the full SHA")
  H.eq(#git.head_hash({ dir = repo }), 40, "...40 hex characters, not abbreviated")
  H.eq(
    git.head_short_hash({ dir = repo }),
    short,
    "head_short_hash({dir}): unchanged, still abbreviated"
  )
  H.ok(
    #git.head_hash({ dir = repo }) > #git.head_short_hash({ dir = repo }),
    "the full hash is longer than the short one"
  )

  H.eq(
    git.describe({ dir = repo }),
    short,
    "describe({dir}): --always falls back to the short hash before any tag exists"
  )

  git_run(repo, { "tag", "v1.2.3" })
  H.eq(git.describe({ dir = repo }), "v1.2.3", "describe({dir}): the tag once one exists")

  vim.fn.writefile({ "y" }, repo .. "/a.txt")
  git_run(repo, { "add", "-A" })
  git_run(repo, { "commit", "-q", "-m", "second" })
  local expected_describe = git_run(repo, { "describe", "--tags", "--always" })
  H.eq(
    git.describe({ dir = repo }),
    expected_describe,
    "describe({dir}): commits past a tag describe as <tag>-<n>-g<hash>"
  )
  H.ok(
    git.describe({ dir = repo }):find("v1.2.3", 1, true) ~= nil,
    "...still names the tag it is counted from"
  )

  -- Failure shape: both return nil outside a repo, same as their siblings
  -- (repo_root, current_branch, ...) -- no error string, by the existing
  -- convention of the read-cwd helpers this module predates.
  local not_repo = tmpdir("-not-a-repo")
  H.eq(git.head_hash({ dir = not_repo }), nil, "head_hash({dir}): nil outside a repo")
  H.eq(git.describe({ dir = not_repo }), nil, "describe({dir}): nil outside a repo")

  for _, dir in ipairs(created) do
    pcall(vim.fn.delete, dir, "rf")
  end
end
