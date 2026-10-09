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
    -- (a runtime that embeds its sources stamps `vim/_core/system:324:`, no extension)
    H.ok(
      not err:find("vim[/\\][%w_/\\.]*:%d+:"),
      what .. ": ... without a vim/...:N stamp: " .. err
    )
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

  -- ── no_lazy_fetch also pins GIT_ALLOW_PROTOCOL ─────────────────────────
  -- (a per-protocol `protocol.<name>.allow` in a repository's config beats
  -- `-c protocol.allow=never`; GIT_ALLOW_PROTOCOL beats both)
  local proto_probe = H.tmpfile(".lua")
  vim.fn.writefile({ 'io.stdout:write(os.getenv("GIT_ALLOW_PROTOCOL") or "unset")' }, proto_probe)
  local proto_git = { "-n", "-i", "NONE", "--headless", "-u", "NONE", "-l", proto_probe }
  H.eq(
    git.run(proto_git, nil, vim.v.progpath).stdout,
    "unset",
    "run: GIT_ALLOW_PROTOCOL is not touched unless asked"
  )
  H.eq(
    git.run(proto_git, { no_lazy_fetch = true }, vim.v.progpath).stdout,
    "none",
    "run: no_lazy_fetch sets GIT_ALLOW_PROTOCOL=none"
  )
  H.eq(
    git.run(
      proto_git,
      { no_lazy_fetch = true, env = { GIT_ALLOW_PROTOCOL = "https" } },
      vim.v.progpath
    ).stdout,
    "https",
    "run: an explicit GIT_ALLOW_PROTOCOL wins over the no_lazy_fetch default"
  )
  vim.fn.delete(proto_probe)

  -- ── rev_parse of a full hash that is not in the repository ──────────────
  local extra = F.init("-git-run-extra")
  F.write(extra .. "/a.txt", "a\n")
  local e1 = F.commit(extra, "one", { when = BASE + 100 })
  H.eq(git.rev_parse(e1, { dir = extra }), e1, "rev_parse: a full hash that exists resolves")
  H.eq(
    git.rev_parse(("1"):rep(40), { dir = extra }),
    nil,
    "rev_parse: a well-formed full hash of an object that does not exist is not 'resolved'"
  )
  H.eq(
    git.rev_parse("HEAD:a.txt", { dir = extra }),
    F.git(extra, { "rev-parse", "HEAD:a.txt" }),
    "rev_parse: other forms are untouched"
  )

  -- ── tags: only a tag that points at a commit says commit = true ─────────
  F.git(extra, { "tag", "light" })
  F.git(extra, { "tag", "-a", "-m", "annotated", "ann" })
  F.git(extra, { "tag", "-a", "-m", "nested", "nested", "ann" })
  F.git(extra, { "tag", "treetag", "HEAD^{tree}" })
  F.git(extra, { "tag", "blobtag", "HEAD:a.txt" })
  F.git(extra, { "tag", "-a", "-m", "on a tree", "anntree", "HEAD^{tree}" })
  local by_name = {}
  for _, t in ipairs(git.tags({ dir = extra }) or {}) do
    by_name[t.name] = t
  end
  for name, want in pairs({
    light = true,
    ann = true,
    nested = true,
    treetag = false,
    blobtag = false,
    anntree = false,
  }) do
    H.ok(by_name[name] ~= nil, "tags: " .. name .. " is listed")
    H.eq((by_name[name] or {}).commit, want, "tags: " .. name .. " .commit")
  end
  H.eq(by_name.light.sha, e1, "tags: a lightweight tag on a commit has that commit as sha")
  H.eq(by_name.ann.sha, e1, "tags: an annotated one is peeled")
  H.eq(by_name.nested.sha, e1, "tags: a tag on a tag is peeled down to the commit")
  H.eq(by_name.nested.annotated, true, "tags: ... and is annotated")
  -- the async counterpart gives the same answer (one more question for a nested tag)
  local async_tags
  git.tags_async({ dir = extra }, function(list)
    async_tags = list
  end)
  wait_for(function()
    return async_tags ~= nil
  end)
  local async_by_name = {}
  for _, t in ipairs(async_tags) do
    async_by_name[t.name] = t
  end
  H.eq(async_by_name.nested.commit, true, "tags_async: a tag on a tag points at a commit")
  H.eq(async_by_name.nested.sha, e1, "tags_async: ... and carries that commit as sha")
  H.eq(async_by_name.anntree.commit, false, "tags_async: an annotated tag on a tree is none")

  -- a failing peel is an error, never the one-level answer as if it were the final one
  -- (POSIX: the wrapper is a shell script that lets everything through but `cat-file`)
  if vim.fn.has("win32") == 0 then
    local wrapper = vim.fn.tempname() .. "-git-no-cat-file"
    local fh = assert(io.open(wrapper, "w"))
    fh:write('#!/bin/sh\nfor a in "$@"; do [ "$a" = cat-file ] && exit 3; done\nexec git "$@"\n')
    fh:close()
    vim.uv.fs_chmod(wrapper, 493) -- 0755
    local fail_tags, fail_err = git.tags({ dir = extra }, wrapper)
    H.eq(fail_tags, nil, "tags: a failing cat-file is an error")
    H.ok(type(fail_err) == "string" and fail_err ~= "", "tags: ... with a reason")
    local fail_box
    git.tags_async({ dir = extra }, function(list, err)
      fail_box = { list = list, err = err }
    end, wrapper)
    wait_for(function()
      return fail_box ~= nil
    end)
    H.eq(fail_box.list, nil, "tags_async: ... and so is it asynchronously")
    H.ok(type(fail_box.err) == "string", "tags_async: ... with a reason")
    os.remove(wrapper)
  end

  -- a tag on a tag on a tag: one hop per round
  F.git(extra, { "tag", "-a", "-m", "third", "third", "nested" })
  local deep = {}
  for _, t in ipairs(git.tags({ dir = extra }) or {}) do
    deep[t.name] = t
  end
  H.eq(deep.third and deep.third.commit, true, "tags: a chain of three tags reaches the commit")
  H.eq(deep.third and deep.third.sha, e1, "tags: ... and its sha")

  -- sync and async agree at the round limit: a chain of exactly 64 hops still works, 65 is too long
  local long_dir = vim.fn.tempname() .. "-long-chain"
  vim.fn.mkdir(long_dir, "p")
  F.git(long_dir, { "init", "-q" })
  F.git(
    long_dir,
    { "-c", "user.email=a@b", "-c", "user.name=n", "commit", "-q", "--allow-empty", "-m", "c" }
  )
  F.git(long_dir, { "-c", "user.email=a@b", "-c", "user.name=n", "tag", "-a", "-m", "x", "c0" })
  for i = 1, 65 do
    F.git(long_dir, {
      "-c",
      "advice.nestedTag=false",
      "-c",
      "user.email=a@b",
      "-c",
      "user.name=n",
      "tag",
      "-a",
      "-m",
      "x",
      "c" .. i,
      "c" .. (i - 1),
    })
  end
  --- Runs `tags` both ways on one tag of the chain.
  local function both_ways(name)
    local sync_tags, sync_err = git.tags({ dir = long_dir, pattern = name })
    local box
    git.tags_async({ dir = long_dir, pattern = name }, function(list, err)
      box = { list = list, err = err }
    end)
    wait_for(function()
      return box ~= nil
    end)
    return sync_tags, sync_err, box.list, box.err
  end
  local st, se, at, ae = both_ways("c64") -- 64 hops: the last allowed
  H.ok(st ~= nil and se == nil and st[1].commit == true, "tags: a chain of 64 hops peels")
  H.ok(at ~= nil and ae == nil and at[1].commit == true, "tags_async: ... and so does it")
  st, se, at, ae = both_ways("c65") -- 65 hops: one too many
  H.ok(st == nil and type(se) == "string", "tags: a chain of 65 hops is an error")
  H.ok(at == nil and type(ae) == "string", "tags_async: ... and so it is asynchronously")
  vim.fn.delete(long_dir, "rf")

  -- stop() between rounds: once stopped, no further round starts and on_done says so
  local stop_box, stop_handle
  stop_handle = git.tags_async({ dir = extra }, function(list, err)
    stop_box = { list = list, err = err }
  end)
  stop_handle.stop()
  wait_for(function()
    return stop_box ~= nil
  end)
  H.eq(stop_box.list, nil, "tags_async: a stopped call reports no tags")
  H.ok(type(stop_box.err) == "string", "tags_async: ... but a reason")
  H.eq(by_name.treetag.time, nil, "tags: a tag on a tree has no commit date")

  -- ── merge_base: a killed process is 'unknown', not 'no common ancestor' ─
  local run_argv = require("lib.nvim.cross.run_argv")
  local mb_box
  H.with_patched(run_argv, "run_async_captured", function(_, on_done)
    -- Windows reports a stop()ped process as exit code 1 with a signal
    vim.schedule(function()
      on_done(false, "", 1, "", 15)
    end)
    return { stop = function() end }
  end, function()
    git.merge_base_async("main", "side", { dir = extra }, function(sha, err)
      mb_box = { sha = sha, err = err }
    end)
    wait_for(function()
      return mb_box ~= nil
    end)
  end)
  H.eq(mb_box and mb_box.sha, nil, "merge_base_async: a killed process gives no answer")
  H.ok(
    mb_box and mb_box.err and mb_box.err:find("signal 15", 1, true),
    "merge_base_async: ... and says it was terminated, not 'no common ancestor'"
  )

  -- ── the async runner answers at the deadline, once ─────────────────────
  local calls = 0
  local late_box
  git.run_async(
    { "-n", "-i", "NONE", "--headless", "-u", "NONE", "-l", sleeper },
    { timeout_ms = 200 },
    function(res)
      calls = calls + 1
      late_box = res
    end,
    vim.v.progpath
  )
  wait_for(function()
    return late_box ~= nil
  end)
  vim.wait(300) -- a second delivery would show up here
  H.eq(calls, 1, "run_async timeout: on_done is called exactly once")
  H.eq((late_box or {}).timed_out, true, "run_async timeout: ... and it is a timeout")

  F.cleanup()
  vim.fn.delete(probe)
  vim.fn.delete(sleeper)
end
