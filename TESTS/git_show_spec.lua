-- TESTS/git_show_spec.lua — lib.nvim.git.show / show_async
--
-- The point of `show` is that the content arrives byte for byte: a CRLF file
-- keeps its `\r\n`, a binary blob keeps every byte, an empty file is `""`
-- (not nil). `vim.system` rewrites `\r\n` when it runs in text mode, which is
-- what `run_argv` does by default -- so the CRLF and binary assertions below
-- are the ones that catch a `show` that went through the text path.
--
-- Fixtures are real throwaway repositories, not string mocks.

return function(H)
  local git = require("lib.nvim.git")

  local created = {} ---@type string[]

  local function tmpdir(suffix)
    local dir = vim.fn.tempname() .. suffix
    vim.fn.mkdir(dir, "p")
    created[#created + 1] = dir
    return dir
  end

  --- A fixture step that fails is a test failure, never a silent skip.
  ---@param dir string
  ---@param args string[]
  ---@param allow_fail? boolean
  ---@return string stdout
  ---@return integer code
  local function git_run(dir, args, allow_fail)
    local argv = {
      "git",
      "-c",
      "user.name=lib-nvim-spec",
      "-c",
      "user.email=spec@example.invalid",
      "-c",
      "commit.gpgsign=false",
      "-c",
      "core.autocrlf=false",
      "-C",
      dir,
    }
    vim.list_extend(argv, args)
    local res = vim.system(argv, { text = true }):wait()
    if not allow_fail then
      H.ok(
        res.code == 0,
        ("fixture: git %s failed (%d): %s"):format(table.concat(args, " "), res.code, res.stderr)
      )
    end
    return vim.trim(res.stdout or ""), res.code
  end

  local function write_bytes(path, text)
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
  end

  local function wait_for(pred)
    vim.wait(5000, pred, 10)
    return pred()
  end

  -- Every byte value that a text-mode read would touch: `\r\n`, a lone `\r`,
  -- `NUL`, and high bytes that are not valid UTF-8.
  local BINARY = "\0\1\255\254\r\n\0\r\rend\128"
  local CRLF = "line a\r\nline b\r\n"

  local repo = tmpdir("-git-show-repo")
  git_run(repo, { "init", "-q", "-b", "main" })
  write_bytes(repo .. "/a b.txt", "one\n")
  write_bytes(repo .. "/ü.txt", "umlaut one\n")
  write_bytes(repo .. "/dir/nested file.txt", "nested one\n")
  write_bytes(repo .. "/crlf.txt", CRLF)
  write_bytes(repo .. "/bin.dat", BINARY)
  write_bytes(repo .. "/empty.txt", "")
  git_run(repo, { "add", "-A" })
  git_run(repo, { "commit", "-q", "-m", "v1" })
  git_run(repo, { "tag", "v1" })

  write_bytes(repo .. "/a b.txt", "two\n")
  git_run(repo, { "commit", "-q", "-am", "v2" })
  git_run(repo, { "branch", "feature" })
  local v1_hash = git_run(repo, { "rev-parse", "v1" })

  -- Staged "three", then an unstaged "four" on top: index and worktree differ.
  write_bytes(repo .. "/a b.txt", "three\n")
  git_run(repo, { "add", "a b.txt" })
  write_bytes(repo .. "/a b.txt", "four\n")

  -- ── revisions ───────────────────────────────────────────────────────
  local function show(rev, path, opts)
    return git.show(rev, path, opts or { dir = repo })
  end

  H.eq(show("HEAD", "a b.txt"), "two\n", "show: HEAD (a path with a space)")
  H.eq(show("HEAD~1", "a b.txt"), "one\n", "show: HEAD~1")
  H.eq(show("v1", "a b.txt"), "one\n", "show: a tag")
  H.eq(show("feature", "a b.txt"), "two\n", "show: a branch")
  H.eq(show(v1_hash, "a b.txt"), "one\n", "show: a full commit hash")
  H.eq(show("HEAD", "ü.txt"), "umlaut one\n", "show: a non-ASCII path")
  H.eq(show("", "a b.txt"), "three\n", 'show: rev "" is the staged version, not the worktree')

  -- ── byte-exactness: the reason this function exists ─────────────────
  H.eq(show("HEAD", "crlf.txt"), CRLF, "show: a CRLF blob keeps every \\r\\n")
  local bin = show("HEAD", "bin.dat")
  H.eq(#bin, #BINARY, "show: a binary blob keeps its length")
  H.eq(bin, BINARY, "show: ...and every byte (NUL, lone \\r, invalid UTF-8)")

  local empty, empty_err = show("HEAD", "empty.txt")
  H.eq(empty, "", "show: an empty file is the empty string, not nil")
  H.eq(empty_err, nil, "show: ...and not an error")

  -- ── path resolution ─────────────────────────────────────────────────
  H.eq(
    show("HEAD", "dir/nested file.txt"),
    "nested one\n",
    "show: relative to opts.dir, a nested path"
  )
  H.eq(
    git.show("HEAD", "nested file.txt", { dir = repo .. "/dir" }),
    "nested one\n",
    "show: a path relative to a SUBDIRECTORY dir, not to the repo root"
  )
  H.eq(
    git.show("HEAD", "../a b.txt", { dir = repo .. "/dir" }),
    "two\n",
    "show: `..` from a subdirectory"
  )
  H.eq(
    git.show("HEAD", repo .. "/dir/nested file.txt"),
    "nested one\n",
    "show: an absolute path needs neither opts nor the cwd to be the repo"
  )
  if vim.fn.has("win32") == 1 then
    H.eq(show("HEAD", "dir\\nested file.txt"), "nested one\n", "show: backslashes on Windows")
  end

  -- ── failure shape: nil + err, never an error, never "" ──────────────
  for label, args in pairs({
    ["an unknown revision"] = { "no-such-revision", "a b.txt" },
    ["a path that is not in that revision"] = { "HEAD", "not-there.txt" },
    ["a path that exists only in the worktree"] = { "v1", "later.txt" },
  }) do
    write_bytes(repo .. "/later.txt", "x")
    local ok_call, content, err = pcall(show, args[1], args[2])
    H.ok(ok_call, "show: " .. label .. " does not raise")
    H.eq(content, nil, "show: " .. label .. " is nil")
    H.ok(type(err) == "string" and #err > 0, "show: " .. label .. " says why")
  end

  local not_repo = tmpdir("-not-a-repo")
  local outside, outside_err = git.show("HEAD", "a b.txt", { dir = not_repo })
  H.eq(outside, nil, "show: outside a repository is nil")
  H.ok(type(outside_err) == "string", "show: ...with an error")

  local no_bin, no_bin_err =
    git.show("HEAD", "a b.txt", { dir = repo }, "definitely-not-a-git-binary-lib-nvim-spec")
  H.eq(no_bin, nil, "show: an unspawnable git is nil")
  H.ok(
    type(no_bin_err) == "string" and not no_bin_err:find("unknown revision", 1, true),
    "show: ...with the spawn failure, not the generic 'unknown revision' hint"
  )

  -- ── arguments that must not reach git ───────────────────────────────
  -- `rev` is glued to the front of one argument, so a leading `-` would be
  -- read as an option. `--pretty=format:` makes `git show` SUCCEED with output
  -- on a naive implementation: the assertion is that nothing came back.
  local injected, inject_err = show("--pretty=format:INJECTED", "a b.txt")
  H.eq(injected, nil, "show: a revision starting with `-` is refused, not passed to git")
  H.ok(type(inject_err) == "string" and inject_err:find("invalid revision", 1, true) ~= nil)
  H.eq((show("HEAD\nsecond", "a b.txt")), nil, "show: a revision with a newline is refused")
  H.eq((show(nil, "a b.txt")), nil, "show: a non-string revision is refused")
  H.eq((show("HEAD", "")), nil, "show: an empty path is refused")
  H.eq((show("HEAD", nil)), nil, "show: a non-string path is refused")

  -- The pre-`opts` calling convention (git_cmd where opts belongs) is loud.
  local ok_legacy = pcall(git.show, "HEAD", "a b.txt", "some-git")
  H.eq(ok_legacy, false, "show: a string where opts belongs raises")

  -- ── merge stages: `:1` base, `:2` ours, `:3` theirs ─────────────────
  local merge = tmpdir("-git-show-merge")
  git_run(merge, { "init", "-q", "-b", "main" })
  write_bytes(merge .. "/c.txt", "base\n")
  git_run(merge, { "add", "-A" })
  git_run(merge, { "commit", "-q", "-m", "base" })
  git_run(merge, { "checkout", "-q", "-b", "other" })
  write_bytes(merge .. "/c.txt", "theirs\n")
  git_run(merge, { "commit", "-q", "-am", "theirs" })
  git_run(merge, { "checkout", "-q", "main" })
  write_bytes(merge .. "/c.txt", "ours\n")
  git_run(merge, { "commit", "-q", "-am", "ours" })
  local _, merge_code = git_run(merge, { "merge", "other" }, true)
  H.ok(merge_code ~= 0, "fixture: the merge must conflict, or this proves nothing")

  H.eq(git.show(":1", "c.txt", { dir = merge }), "base\n", "show: `:1` is the common ancestor")
  H.eq(git.show(":2", "c.txt", { dir = merge }), "ours\n", "show: `:2` is ours")
  H.eq(git.show(":3", "c.txt", { dir = merge }), "theirs\n", "show: `:3` is theirs")
  H.eq(
    (git.show("", "c.txt", { dir = merge })),
    nil,
    "show: there is no stage-0 entry while the path is unmerged"
  )

  -- ── async ───────────────────────────────────────────────────────────
  do
    local done, content, err = false, "unset", "unset"
    git.show_async("HEAD", "crlf.txt", { dir = repo }, function(c, e)
      done, content, err = true, c, e
    end)
    H.ok(
      wait_for(function()
        return done
      end),
      "show_async: on_done fires"
    )
    H.eq(content, CRLF, "show_async: byte for byte, like the synchronous call")
    H.eq(err, nil, "show_async: no error")
  end

  do
    local done, content, err = false, "unset", nil
    git.show_async("HEAD", "bin.dat", nil, function(c, e)
      done, content, err = true, c, e
    end)
    -- opts = nil reads the cwd (this checkout): bin.dat is not in it, so this
    -- is the failure path with a nil opts -- callback-first form is valid.
    H.ok(
      wait_for(function()
        return done
      end),
      "show_async: opts = nil is accepted"
    )
    H.eq(content, nil, "show_async: a path that is not in the cwd's repo is nil")
    H.ok(type(err) == "string" and #err > 0, "show_async: ...with an error")
  end

  do
    local done, content, err = false, "unset", nil
    git.show_async("HEAD", "binary.dat", { dir = repo }, function(c, e)
      done, content, err = true, c, e
    end)
    H.ok(
      wait_for(function()
        return done
      end),
      "show_async: on_done fires on failure"
    )
    H.eq(content, nil, "show_async: a missing path is nil")
    H.ok(type(err) == "string", "show_async: ...with an error")
  end

  do
    local done, content, err = false, "unset", nil
    local returned = git.show_async("--output=x", "a b.txt", { dir = repo }, function(c, e)
      done, content, err = true, c, e
    end)
    H.eq(type(returned.stop), "function", "show_async: a refused call still returns a handle")
    H.ok(
      wait_for(function()
        return done
      end),
      "show_async: a refused call still reaches on_done (scheduled)"
    )
    H.eq(content, nil, "show_async: a bad revision is nil")
    H.ok(type(err) == "string" and err:find("invalid revision", 1, true) ~= nil)
  end

  -- Best-effort cleanup; on Windows a just-used .git can hold read-only files,
  -- and a leftover temp directory is not a test failure.
  for _, dir in ipairs(created) do
    pcall(vim.fn.delete, dir, "rf")
  end
end
