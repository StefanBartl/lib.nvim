-- TESTS/git_run_spec.lua — lib.nvim.git.run / run_async / rev_parse /
-- merge_base / is_ancestor / tags, and the creatordate ordering of refs
--
-- The runner options (timeout, environment) are exercised with a child
-- Neovim standing in for the `git` binary (`git_cmd` is the last parameter of
-- every function): it can print its environment and sleep, which git cannot.
-- Everything else runs against real throwaway repositories.

return function(H)
  local git = require("lib.nvim.git")
  local dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
  local F = dofile(dir .. "git_fixture.lua")(H)

  local function wait_for(pred)
    vim.wait(10000, pred, 10)
    return pred()
  end

  local function no_position(err, what)
    H.ok(type(err) == "string" and err ~= "", what .. ": a message is returned")
    H.ok(not err:find("%.lua:%d+:"), what .. ": ... without a Lua file:line stamp: " .. err)
  end

  -- ── run / run_async: the generic runner ─────────────────────────────────
  local repo = F.init("-git-run-repo")
  local BASE = 1700000000
  F.write(repo .. "/a.txt", "a\n")
  local c1 = F.commit(repo, "one", { when = BASE + 100 })

  local head = git.run({ "rev-parse", "HEAD" }, { dir = repo })
  H.eq(head.ok, true, "run: ok on exit 0")
  H.eq(head.code, 0, "run: exit code")
  H.eq(vim.trim(head.stdout), c1, "run: stdout")
  H.eq(head.stderr, "", 'run: an empty stderr is "", not nil')
  H.eq(head.timed_out, false, "run: not timed out")

  local failed = git.run({ "rev-parse", "--verify", "no-such-rev" }, { dir = repo })
  H.eq(failed.ok, false, "run: a failing command is not ok")
  H.ok(failed.code ~= 0, "run: ... and has its exit code")
  -- (not matched against git's wording: a localised git says it in another language)
  H.ok(failed.stderr and failed.stderr ~= "", "run: ... and git's own stderr")

  local readonly = git.run({ "rev-parse", "HEAD" }, { dir = repo, read_only = true })
  H.eq(vim.trim(readonly.stdout), c1, "run: read_only (--no-optional-locks) still works")

  H.eq(pcall(git.run, {}), false, "run: no arguments is a programming error")
  H.eq(pcall(git.run, "log"), false, "run: arguments must be a list")
  H.eq(pcall(git.run, { "log" }, "not-a-table"), false, "run: opts must be a table")

  local nobin = git.run({ "--version" }, nil, "git-binary-that-does-not-exist")
  H.eq(nobin.ok, false, "run: a binary that cannot be started is not ok")
  H.eq(nobin.code, -1, "run: ... with code -1")
  H.eq(nobin.timed_out, false, "run: ... which is not a timeout")
  H.eq(nobin.stdout, "", "run: ... and no stdout")
  no_position(nobin.stderr, "run spawn failure")

  -- A child Neovim in place of git: prints what the runner passed it.
  local probe = H.tmpfile(".lua")
  vim.fn.writefile({
    'io.stdout:write((os.getenv("GIT_NO_LAZY_FETCH") or "unset") .. "|"',
    '  .. (os.getenv("FOO") or "unset"))',
  }, probe)
  local fake_git = { "-n", "-i", "NONE", "--headless", "-u", "NONE", "-l", probe }

  local plain = git.run(fake_git, nil, vim.v.progpath)
  H.eq(plain.stdout, "unset|unset", "run: nothing is set unless asked")
  local with_env = git.run(fake_git, { env = { FOO = "bar" } }, vim.v.progpath)
  H.eq(with_env.stdout, "unset|bar", "run: env reaches the process")
  local lazy = git.run(fake_git, { no_lazy_fetch = true }, vim.v.progpath)
  H.eq(lazy.stdout, "1|unset", "run: no_lazy_fetch sets GIT_NO_LAZY_FETCH=1")
  local both = git.run(
    fake_git,
    { no_lazy_fetch = true, env = { FOO = "bar", GIT_NO_LAZY_FETCH = "0" } },
    vim.v.progpath
  )
  H.eq(both.stdout, "0|bar", "run: an explicit env entry wins over the no_lazy_fetch default")

  -- A process that outlives its timeout is killed and says so.
  local sleeper = H.tmpfile(".lua")
  vim.fn.writefile({ "vim.wait(60000, function() return false end, 50)" }, sleeper)
  local slow = git.run(
    { "-n", "-i", "NONE", "--headless", "-u", "NONE", "-l", sleeper },
    { timeout_ms = 300 },
    vim.v.progpath
  )
  H.eq(slow.ok, false, "run timeout: not ok")
  H.eq(slow.timed_out, true, "run timeout: timed_out")
  H.eq(slow.code, 124, "run timeout: the timeout(1) exit code")

  -- async
  local async_res
  local handle = git.run_async({ "rev-parse", "HEAD" }, { dir = repo }, function(res)
    async_res = res
  end)
  H.eq(type(handle.stop), "function", "run_async: a stoppable handle")
  H.ok(
    wait_for(function()
      return async_res ~= nil
    end),
    "run_async: on_done fires"
  )
  H.eq(vim.trim((async_res or {}).stdout), c1, "run_async: the same result as run")
  H.eq((async_res or {}).code, 0, "run_async: exit code")

  local async_fail
  git.run_async({ "--version" }, nil, function(res)
    async_fail = res
  end, "git-binary-that-does-not-exist")
  H.ok(
    wait_for(function()
      return async_fail ~= nil
    end),
    "run_async: a spawn failure reports"
  )
  H.eq((async_fail or {}).code, -1, "run_async: ... with code -1")
  H.eq((async_fail or {}).stdout, "", "run_async: ... and an empty stdout")
  no_position((async_fail or {}).stderr, "run_async spawn failure (reason in stderr)")

  local async_slow
  git.run_async(
    { "-n", "-i", "NONE", "--headless", "-u", "NONE", "-l", sleeper },
    { timeout_ms = 300 },
    function(res)
      async_slow = res
    end,
    vim.v.progpath
  )
  H.ok(
    wait_for(function()
      return async_slow ~= nil
    end),
    "run_async timeout: reports"
  )
  H.eq((async_slow or {}).timed_out, true, "run_async timeout: timed_out")

  -- ── history for rev_parse / merge_base / is_ancestor / tags ─────────────
  --   c1 --- c2 (main, tag v1 lightweight, v2 annotated)
  --      \-- s1 (side, tag v1.10)
  F.write(repo .. "/a.txt", "b\n")
  local c2 = F.commit(repo, "two", { when = BASE + 200 })
  F.git(repo, { "tag", "v1.2" }, { env = F.when(BASE + 200) })
  F.git(repo, { "tag", "-a", "v2", "-m", "release two" }, { env = F.when(BASE + 300) })
  F.git(repo, { "checkout", "-q", "-b", "side", c1 })
  F.write(repo .. "/s.txt", "s\n")
  local s1 = F.commit(repo, "side", { when = BASE + 250 })
  F.git(repo, { "tag", "v1.10" }, { env = F.when(BASE + 250) })
  F.git(repo, { "checkout", "-q", "main" })
  local v2_object = F.git(repo, { "rev-parse", "v2" })

  -- rev_parse
  H.eq(git.rev_parse("HEAD", { dir = repo }), c2, "rev_parse: HEAD, the full name")
  H.eq(git.rev_parse("main", { dir = repo }), c2, "rev_parse: a branch")
  -- (git's default abbreviation length is configurable, so only the prefix is pinned)
  local short = git.rev_parse("HEAD", { dir = repo, short = true })
  H.ok(#short >= 4 and #short < #c2 and c2:sub(1, #short) == short, "rev_parse: short is a prefix")
  H.eq(#git.rev_parse("HEAD", { dir = repo, short = 10 }), 10, "rev_parse: short with a length")
  H.eq(git.rev_parse("HEAD~1", { dir = repo }), c1, "rev_parse: an ancestor expression")
  H.eq(git.rev_parse("v2", { dir = repo }), v2_object, "rev_parse: an annotated tag is its object")
  H.eq(
    git.rev_parse("v2", { dir = repo, commit = true }),
    c2,
    "rev_parse commit: ... or the commit it points to, when peeled"
  )
  local unknown, unknown_err = git.rev_parse("no-such-rev", { dir = repo })
  H.eq(unknown, nil, "rev_parse: an unknown revision is nil")
  no_position(unknown_err, "rev_parse unknown revision")
  local dashed, dashed_err = git.rev_parse("--all", { dir = repo })
  H.eq(dashed, nil, "rev_parse: an option-looking revision is refused")
  H.ok(dashed_err and dashed_err:find("invalid revision", 1, true), "rev_parse: ... with a reason")
  H.eq(git.rev_parse("", { dir = repo }), nil, "rev_parse: an empty revision is refused")
  H.eq(git.rev_parse("a\nb", { dir = repo }), nil, "rev_parse: a revision with a line break")

  -- merge_base
  H.eq(git.merge_base("main", "side", { dir = repo }), c1, "merge_base: where the branches split")
  H.eq(git.merge_base("main", "main", { dir = repo }), c2, "merge_base: a revision with itself")
  local orphan = F.init("-orphan")
  F.write(orphan .. "/o.txt", "o\n")
  local o_sha = F.commit(orphan, "orphan", { when = BASE + 10 })
  F.git(repo, { "fetch", "-q", orphan, "main:foreign" })
  local none, none_err = git.merge_base("main", "foreign", { dir = repo })
  H.eq(none, nil, "merge_base: unrelated histories have none")
  H.eq(none_err, "no common ancestor", "merge_base: ... said plainly")
  H.eq(git.rev_parse("foreign", { dir = repo }), o_sha, "fixture: the foreign branch is the orphan")
  local mb_bad, mb_bad_err = git.merge_base("main", "no-such-rev", { dir = repo })
  H.eq(mb_bad, nil, "merge_base: an unknown revision is a failure")
  no_position(mb_bad_err, "merge_base unknown revision")
  H.eq(git.merge_base("--all", "main", { dir = repo }), nil, "merge_base: an option is refused")

  -- is_ancestor
  H.eq(git.is_ancestor(c1, "main", { dir = repo }), true, "is_ancestor: a fast-forward away")
  H.eq(git.is_ancestor("main", c1, { dir = repo }), false, "is_ancestor: the wrong way round")
  H.eq(git.is_ancestor("main", "side", { dir = repo }), false, "is_ancestor: diverged")
  H.eq(git.is_ancestor("main", "main", { dir = repo }), true, "is_ancestor: a revision is its own")
  H.eq(git.is_ancestor("foreign", "main", { dir = repo }), false, "is_ancestor: unrelated")
  local anc, anc_err = git.is_ancestor("no-such-rev", "main", { dir = repo })
  H.eq(anc, nil, "is_ancestor: unknown revision is nil, neither true nor false")
  no_position(anc_err, "is_ancestor unknown revision")
  H.eq(git.is_ancestor("-x", "main", { dir = repo }), nil, "is_ancestor: an option is refused")

  -- tags
  local function names(tags)
    local out = {}
    for _, tag in ipairs(tags) do
      out[#out + 1] = tag.name
    end
    return table.concat(out, ",")
  end

  local tags, tags_err = git.tags({ dir = repo })
  H.ok(tags, "tags: " .. tostring(tags_err))
  tags = tags or {}
  -- newest creator date first: v2 (annotated, BASE+300), v1.10 (+250), v1.2 (+200)
  H.eq(names(tags), "v2,v1.10,v1.2", "tags: newest creator date first, an annotated tag included")
  H.eq(tags[1].annotated, true, "tags: v2 is annotated")
  H.eq(tags[1].object, v2_object, "tags: ... its own object")
  H.eq(tags[1].sha, c2, "tags: ... and the commit it points to, peeled")
  H.eq(tags[1].subject, "release two", "tags: ... with the tag message")
  H.eq(tags[1].time, BASE + 300, "tags: ... and the tagger date")
  H.eq(tags[2].annotated, false, "tags: v1.10 is lightweight")
  H.eq(tags[2].object, s1, "tags: ... its object is the commit")
  H.eq(tags[2].sha, s1, "tags: ... which is also its sha")
  H.eq(tags[2].subject, "side", "tags: ... with the commit subject")
  H.eq(tags[2].time, BASE + 250, "tags: ... and the commit date")

  H.eq(names(git.tags({ dir = repo, sort = "oldest" })), "v1.2,v1.10,v2", "tags: oldest first")
  H.eq(
    names(git.tags({ dir = repo, sort = "version" })),
    "v2,v1.10,v1.2",
    "tags: version order puts v1.10 above v1.2 (a string sort would not)"
  )
  H.eq(names(git.tags({ dir = repo, limit = 2 })), "v2,v1.10", "tags: limit")
  H.eq(#git.tags({ dir = repo, limit = 0 }), 0, "tags: limit 0 is no tags (git's --count=0 is all)")
  H.eq(names(git.tags({ dir = repo, pattern = "v1.*" })), "v1.10,v1.2", "tags: a name pattern")
  H.eq(
    names(git.tags({ dir = repo, merged = "main" })),
    "v2,v1.2",
    "tags merged: the tags reachable from main"
  )
  H.eq(
    names(git.tags({ dir = repo, no_merged = "main" })),
    "v1.10",
    "tags no_merged: the tags main does not contain"
  )
  H.eq(
    names(git.tags({ dir = repo, merged = "side", no_merged = c1 })),
    "v1.10",
    "tags merged+no_merged: the tags of a range"
  )

  local no_tags = F.init("-no-tags")
  F.write(no_tags .. "/x", "x")
  F.commit(no_tags, "x", { when = BASE })
  local empty = git.tags({ dir = no_tags })
  H.eq(#empty, 0, "tags: no tags is {}, not nil")
  local bad_sort, bad_sort_err = git.tags({ dir = repo, sort = "sideways" })
  H.eq(bad_sort, nil, "tags: an unknown sort is refused")
  no_position(bad_sort_err, "tags unknown sort")
  H.eq(git.tags({ dir = repo, limit = -1 }), nil, "tags: a negative limit is refused")
  H.eq(git.tags({ dir = repo, merged = "--all" }), nil, "tags: an option as merged is refused")
  H.eq(git.tags({ dir = repo, pattern = "a\nb" }), nil, "tags: a pattern with a line break")
  local not_repo, not_repo_err = git.tags({ dir = F.tmpdir("-not-a-repo") })
  H.eq(not_repo, nil, "tags: not a repository is nil")
  no_position(not_repo_err, "tags not a repository")

  -- ── refs() sorts by creator date: annotated tags have no committer date ──
  local sorted = F.init("-refs-sort")
  F.write(sorted .. "/x", "1")
  F.commit(sorted, "one", { when = BASE + 100 })
  F.git(sorted, { "tag", "light-old" }, { env = F.when(BASE + 100) })
  F.write(sorted .. "/x", "2")
  F.commit(sorted, "two", { when = BASE + 200 })
  F.git(sorted, { "tag", "-a", "annotated-new", "-m", "new" }, { env = F.when(BASE + 900) })
  local tag_refs = git.refs(sorted, { branches = false, remotes = false })
  H.eq(
    table.concat(tag_refs, ","),
    "annotated-new,light-old",
    "refs: an annotated tag is dated by its tagger date and sorts first, not last"
  )

  -- ── the async twins give the same answers, and refuse asynchronously ────
  local function collect(start)
    local box = { done = false }
    start(function(a, b)
      box.a, box.b, box.done = a, b, true
    end)
    wait_for(function()
      return box.done
    end)
    return box
  end

  local rp = collect(function(cb)
    git.rev_parse_async("HEAD", { dir = repo }, cb)
  end)
  H.eq(rp.a, c2, "rev_parse_async: the same answer")
  local rp_bad = collect(function(cb)
    git.rev_parse_async("no-such-rev", { dir = repo }, cb)
  end)
  H.eq(rp_bad.a, nil, "rev_parse_async: an unknown revision is nil")
  no_position(rp_bad.b, "rev_parse_async unknown revision")

  local mb = collect(function(cb)
    git.merge_base_async("main", "side", { dir = repo }, cb)
  end)
  H.eq(mb.a, c1, "merge_base_async: the same answer")
  local mb_none = collect(function(cb)
    git.merge_base_async("main", "foreign", { dir = repo }, cb)
  end)
  H.eq(mb_none.b, "no common ancestor", "merge_base_async: unrelated histories")

  local anc_yes = collect(function(cb)
    git.is_ancestor_async(c1, "main", { dir = repo }, cb)
  end)
  H.eq(anc_yes.a, true, "is_ancestor_async: a fast-forward away")
  local anc_no = collect(function(cb)
    git.is_ancestor_async("main", "side", { dir = repo }, cb)
  end)
  H.eq(anc_no.a, false, "is_ancestor_async: diverged")
  local anc_unknown = collect(function(cb)
    git.is_ancestor_async("no-such-rev", "main", { dir = repo }, cb)
  end)
  H.eq(anc_unknown.a, nil, "is_ancestor_async: unknown revision is nil, not false")
  H.ok(anc_unknown.b, "is_ancestor_async: ... with a reason")

  local tg = collect(function(cb)
    git.tags_async({ dir = repo, merged = "main" }, cb)
  end)
  H.eq(names(tg.a), "v2,v1.2", "tags_async: the same answer")
  local tg_zero = collect(function(cb)
    git.tags_async({ dir = repo, limit = 0 }, cb)
  end)
  H.eq(#tg_zero.a, 0, "tags_async: limit 0 is no tags")

  -- refused calls report asynchronously, never synchronously
  local refused_box
  git.rev_parse_async("--all", { dir = repo }, function(a, b)
    refused_box = { a = a, b = b }
  end)
  H.eq(refused_box, nil, "rev_parse_async: a refused call does not call back synchronously")
  wait_for(function()
    return refused_box ~= nil
  end)
  H.eq(refused_box.a, nil, "rev_parse_async: ... it reports nil")
  H.ok(refused_box.b:find("invalid revision", 1, true), "rev_parse_async: ... and the reason")
  local sort_box = collect(function(cb)
    git.tags_async({ dir = repo, sort = "sideways" }, cb)
  end)
  H.eq(sort_box.a, nil, "tags_async: an unknown sort is refused asynchronously")

  F.cleanup()
  vim.fn.delete(probe)
  vim.fn.delete(sleeper)
end
