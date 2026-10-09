-- TESTS/git_log_spec.lua — lib.nvim.git.parse_log / log / log_async
--
-- Two halves. The pure parser is fed hand-built output, including the shapes a
-- hostile commit message can take (a forged record marker inside a body) and
-- the ways the output can be broken. `log` runs against real throwaway
-- repositories with a merge, an empty commit, CRLF, non-ASCII paths and a
-- message full of control bytes: what the spec pins is git's actual output,
-- not a mock of it.

return function(H)
  local git = require("lib.nvim.git")
  local dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
  local F = dofile(dir .. "git_fixture.lua")(H)

  local function wait_for(pred)
    vim.wait(10000, pred, 10)
    return pred()
  end

  --- No Lua source position in a message that is returned as a value.
  local function no_position(err, what)
    H.ok(type(err) == "string" and err ~= "", what .. ": a message is returned")
    H.ok(not err:find("%.lua:%d+:"), what .. ": ... without a Lua file:line stamp: " .. err)
  end

  --- `parse_log` that must succeed.
  ---@return Lib.Git.LogEntry[]
  local function parsed(raw, opts)
    local entries, err = git.parse_log(raw, opts)
    H.ok(entries, "parse_log: expected entries, got " .. tostring(err))
    return entries or {}
  end

  -- ── parse_log: the pure parser ──────────────────────────────────────────
  local SHA_A, SHA_B = ("a"):rep(40), ("b"):rep(40)

  --- One record, as `git log -z --format=LOG_FORMAT` prints it (without the
  --- name-status part): RS+sha, nine more fields, then the empty terminator.
  ---@param sha string
  ---@param f? table
  ---@return string
  local function rec(sha, f)
    f = f or {}
    return table.concat({
      "\30" .. sha,
      f.parents or "",
      f.author or "Ann",
      f.email or "ann@example.invalid",
      f.at or "100",
      f.ct or "200",
      f.side or ">",
      f.refs or "",
      f.subject or "subject",
      f.body or "",
      "",
    }, "\0") .. "\0"
  end

  H.eq(#parsed(""), 0, "parse_log: empty output is no commits, not an error")

  local one = parsed(rec(SHA_A, {
    parents = SHA_B .. " " .. ("c"):rep(40),
    at = "1700000100",
    ct = "1700000200",
    refs = "HEAD -> main, tag: v1, origin/main",
    subject = "feat!: x",
    body = "line 1\nBREAKING CHANGE: y\n",
  }))
  H.eq(#one, 1, "parse_log: one record")
  H.eq(one[1].sha, SHA_A, "parse_log: sha")
  H.eq(#one[1].parents, 2, "parse_log: both parents of a merge")
  H.eq(one[1].parents[1], SHA_B, "parse_log: parents keep their order")
  H.eq(one[1].author, "Ann", "parse_log: author")
  H.eq(one[1].email, "ann@example.invalid", "parse_log: email")
  H.eq(one[1].author_time, 1700000100, "parse_log: author time is a number")
  H.eq(one[1].commit_time, 1700000200, "parse_log: committer time is a number")
  H.eq(one[1].subject, "feat!: x", "parse_log: subject")
  H.eq(one[1].body, "line 1\nBREAKING CHANGE: y", "parse_log: body, trailing newline removed")
  H.eq(
    table.concat(one[1].refs, "|"),
    "HEAD -> main|tag: v1|origin/main",
    "parse_log: decorations, split into a list"
  )
  H.eq(one[1].side, nil, "parse_log: no side without left_right (git prints '>' regardless)")
  H.eq(one[1].files, nil, "parse_log: no files without name_status")

  local root = parsed(rec(SHA_A))
  H.eq(#root[1].parents, 0, "parse_log: a root commit has no parents")
  H.eq(#root[1].refs, 0, "parse_log: an undecorated commit has no refs")

  local sides = parsed(rec(SHA_A, { side = "<" }) .. rec(SHA_B, { side = ">" }), {
    left_right = true,
  })
  H.eq(#sides, 2, "parse_log: two records")
  H.eq(sides[1].side, "<", "parse_log: left_right sets the side of the first commit")
  H.eq(sides[2].side, ">", "parse_log: ... and of the second")
  H.eq(
    parsed(rec(SHA_A, { side = "?" }), { left_right = true })[1].side,
    nil,
    "parse_log: an unknown side mark is dropped, not passed through"
  )

  local sha256 = ("d"):rep(64)
  H.eq(parsed(rec(sha256))[1].sha, sha256, "parse_log: a SHA-256 object name is fine")

  -- CRLF from a Windows author: normalised, and the stray \r of the subject goes.
  local crlf = parsed(rec(SHA_A, { subject = "win\r", body = "a\r\nb\r\n" }))
  H.eq(crlf[1].subject, "win", "parse_log: CR removed from the subject")
  H.eq(crlf[1].body, "a\nb", "parse_log: CRLF in the body becomes LF")

  -- The record marker and the old field separators inside a message are just
  -- text: NUL is the separator, and no message can contain one.
  local forged = "\30" .. SHA_B .. "\31forged\31fields"
  local hostile = parsed(rec(SHA_A, { subject = forged, body = forged .. "\n" .. forged }))
  H.eq(#hostile, 1, "parse_log: a forged record marker inside a message forges no record")
  H.eq(hostile[1].sha, SHA_A, "parse_log: ... the real commit is intact")
  H.eq(hostile[1].subject, forged, "parse_log: ... and the forged text stays in the subject")

  -- name-status: the first entry carries git's blank line as a leading "\n".
  local with_files = parsed(
    rec(SHA_A) .. "\nA\0a b.txt\0M\0dir/\195\188.txt\0R100\0old.txt\0new.txt\0" .. rec(SHA_B),
    { name_status = true }
  )
  H.eq(#with_files, 2, "parse_log name_status: file entries do not swallow the next record")
  H.eq(#with_files[1].files, 3, "parse_log name_status: three files")
  H.eq(with_files[1].files[1].status, "A", "parse_log name_status: status")
  H.eq(with_files[1].files[1].path, "a b.txt", "parse_log name_status: a path with a space")
  H.eq(with_files[1].files[2].path, "dir/ü.txt", "parse_log name_status: a non-ASCII path")
  H.eq(with_files[1].files[3].status, "R100", "parse_log name_status: a rename keeps its score")
  H.eq(with_files[1].files[3].path, "new.txt", "parse_log name_status: ... path is the new name")
  H.eq(with_files[1].files[3].orig_path, "old.txt", "parse_log name_status: ... orig_path the old")
  H.eq(#with_files[2].files, 0, "parse_log name_status: a commit without files has an empty list")

  -- A path that merely looks like a record marker is still a path.
  local marker_path = parsed(rec(SHA_A) .. "\nA\0\30" .. SHA_B .. "\0", { name_status = true })
  H.eq(#marker_path, 1, "parse_log name_status: a path shaped like a record marker is a path")
  H.eq(marker_path[1].files[1].path, "\30" .. SHA_B, "parse_log name_status: ... kept verbatim")

  -- Broken output is an error, never a guess.
  local bad, bad_err = git.parse_log("garbage\0")
  H.eq(bad, nil, "parse_log: a stray token is an error")
  no_position(bad_err, "parse_log: stray token")
  H.eq(git.parse_log("\30nothex\0"), nil, "parse_log: a record whose hash is not hex")
  H.eq(
    git.parse_log("\30" .. ("a"):rep(39) .. "\0"),
    nil,
    "parse_log: a hash that is neither 40 nor 64 digits"
  )
  local cut, cut_err = git.parse_log(rec(SHA_A):sub(1, 60))
  H.eq(cut, nil, "parse_log: a record cut short is an error")
  no_position(cut_err, "parse_log: truncated")
  H.eq(
    git.parse_log("\30" .. SHA_A .. ("\0x"):rep(10) .. "\0"),
    nil,
    "parse_log: a record without its empty terminator"
  )
  H.eq(
    git.parse_log(rec(SHA_A) .. "\nR100\0only-one-path\0", { name_status = true }),
    nil,
    "parse_log name_status: a rename that lost its second path"
  )
  H.eq(git.parse_log(nil), nil, "parse_log: a non-string is an error, not a throw")

  -- A hostile commit can carry a message of any size, so the parser must stay
  -- linear: stripping trailing whitespace with the obvious pattern is
  -- quadratic in the length of a whitespace run (200 000 spaces ~ half a
  -- minute); a body of "text, then a wall of blanks, then text" is the worst
  -- case. The bound is generous for slow CI machines, the failure it guards
  -- against is two orders of magnitude beyond it.
  local wall = ("x"):rep(10) .. (" "):rep(200000) .. "y" .. (" \t"):rep(100000)
  local started = vim.uv.hrtime()
  local walled = parsed(rec(SHA_A, { subject = wall, body = wall }))
  local took_ms = (vim.uv.hrtime() - started) / 1e6
  H.ok(
    took_ms < 2000,
    ("parse_log: a 500 KB whitespace run is linear (took %d ms)"):format(took_ms)
  )
  H.eq(#walled[1].body, 10 + 200000 + 1, "parse_log: ... and only the trailing blanks are cut")

  -- ── a real repository ───────────────────────────────────────────────────
  local repo = F.init("-git-log-repo")
  local ctl = "\30" .. ("f"):rep(40) .. "\31fake\31fields"
  -- Git's raw date form needs a plausible epoch (9+ digits), so offset from a base.
  local BASE = 1700000000
  local T = {
    c1 = BASE + 1000,
    c2 = BASE + 2000,
    o1 = BASE + 2500,
    c3 = BASE + 3000,
    merge = BASE + 4000,
    c5 = BASE + 5000,
  }
  local C2_AUTHORED = BASE + 500

  F.write(repo .. "/a b.txt", "one\n")
  F.write(repo .. "/dir/ü.txt", "umlaut\n")
  local c1 = F.commit(
    repo,
    "feat!: first\n\nfirst body line\nBREAKING CHANGE: the old API is gone\n",
    { when = T.c1 }
  )

  F.write(repo .. "/a b.txt", "two\n")
  F.git(repo, { "rm", "-q", "dir/ü.txt" })
  F.write(repo .. "/new.txt", "new\n")
  -- CRLF message; author date long before the commit date (a rebased commit).
  local c2 =
    F.commit(repo, "second\r\n\r\nbody a\r\nbody b\r\n", { when = T.c2, author_when = C2_AUTHORED })
  F.git(repo, { "tag", "-a", "v1", "-m", "release one" }, { env = F.when(T.c2) })

  -- A branch off c2 that main will not contain: the other side of main...other.
  F.git(repo, { "checkout", "-q", "-b", "other" })
  F.write(repo .. "/other.txt", "o\n")
  local o1 = F.commit(repo, "other one", { when = T.o1 })

  F.git(repo, { "checkout", "-q", "main" })
  F.git(repo, { "checkout", "-q", "-b", "side" })
  F.write(repo .. "/side.txt", "s\n")
  local c3 = F.commit(repo, "side one", { when = T.c3 })
  F.git(repo, { "checkout", "-q", "main" })
  F.git(repo, { "merge", "--no-ff", "-q", "side", "-m", "Merge side" }, { env = F.when(T.merge) })
  local merge = F.git(repo, { "rev-parse", "HEAD" })
  -- An empty commit whose message is full of record markers and control bytes.
  local c5 = F.commit(repo, "hostile\n\n" .. ctl .. "\n" .. ctl .. "\n", { when = T.c5 })

  local all, all_err = git.log("HEAD", { dir = repo, name_status = true })
  H.ok(all, "log: HEAD in a real repository: " .. tostring(all_err))
  all = all or {}
  H.eq(#all, 5, "log: five commits from HEAD (the hostile one and the merge included)")
  H.eq(all[1].sha, c5, "log: newest first")
  H.eq(all[2].sha, merge, "log: the merge commit")
  H.eq(all[3].sha, c3, "log: ... then the side commit")
  H.eq(all[4].sha, c2, "log: ... then c2")
  H.eq(all[5].sha, c1, "log: the root commit last")

  H.eq(all[1].subject, "hostile", "log: the hostile commit's subject")
  H.eq(
    all[1].body,
    ctl .. "\n" .. ctl,
    "log: ... its body, record markers and control bytes intact"
  )
  H.eq(#all[1].files, 0, "log name_status: an empty commit has no files")
  H.ok(vim.tbl_contains(all[1].refs, "HEAD -> main"), "log: HEAD is a decoration of the tip")

  H.eq(#all[2].parents, 2, "log: a merge has two parents")
  H.eq(all[2].subject, "Merge side", "log: the merge's subject")
  H.eq(#all[2].files, 0, "log name_status: a merge has no files (no combined diff)")

  H.eq(all[4].author_time, C2_AUTHORED, "log: author time is the author date")
  H.eq(all[4].commit_time, T.c2, "log: commit time is the committer date, not the author date")
  H.eq(all[4].subject, "second", "log: a CRLF message's subject has no \\r")
  H.eq(all[4].body, "body a\nbody b", "log: ... and its body is LF")
  H.ok(vim.tbl_contains(all[4].refs, "tag: v1"), "log: a tag is a decoration of its commit")
  local by_path = {}
  for _, file in ipairs(all[4].files) do
    by_path[file.path] = file.status
  end
  H.eq(by_path["a b.txt"], "M", "log name_status: a modified file, path with a space exact")
  H.eq(by_path["dir/ü.txt"], "D", "log name_status: a deleted file, non-ASCII path exact")
  H.eq(by_path["new.txt"], "A", "log name_status: an added file")
  H.eq(#all[4].files, 3, "log name_status: exactly the three changes")

  H.eq(#all[5].parents, 0, "log: the root commit has no parents")
  H.eq(
    all[5].body,
    "first body line\nBREAKING CHANGE: the old API is gone",
    "log: a body keeps its footer"
  )
  H.eq(#all[5].files, 2, "log name_status: the root commit adds both files")

  -- without name_status there are no files at all
  H.eq(git.log("HEAD", { dir = repo })[1].files, nil, "log: no files unless asked for")
  -- range nil / "" are HEAD
  H.eq(#git.log(nil, { dir = repo }), 5, "log: a nil range is HEAD")
  H.eq(#git.log("", { dir = repo }), 5, "log: an empty range is HEAD")

  -- A file named like a branch must not make the range "ambiguous": a clone
  -- with a `doc` directory next to a `doc` branch, or a `v1` file next to a
  -- `v1` tag, is ordinary.
  F.write(repo .. "/side", "same name as the branch\n")
  F.write(repo .. "/v1", "same name as the tag\n")
  H.eq(#git.log("side", { dir = repo }), 3, "log: a range named like a file in the work tree")
  H.eq(#git.log("v1", { dir = repo }), 2, "log: ... a tag named like a file too")
  vim.fn.delete(repo .. "/side")
  vim.fn.delete(repo .. "/v1")

  -- symmetric difference with the side of every commit
  local sym = git.log("main...other", { dir = repo, left_right = true })
  H.eq(#sym, 4, "log left_right: three commits only on main, one only on other")
  local side_of = {}
  for _, entry in ipairs(sym) do
    side_of[entry.subject] = entry.side
  end
  H.eq(side_of["hostile"], "<", "log left_right: only on the left (main)")
  H.eq(side_of["Merge side"], "<", "log left_right: ... the merge too")
  H.eq(side_of["side one"], "<", "log left_right: ... and the side commit")
  H.eq(side_of["other one"], ">", "log left_right: only on the right (other)")
  H.eq(sym[#sym].sha ~= o1 or side_of["other one"] == ">", true, "log left_right: o1 is listed")

  -- ordering and limits
  local rev = git.log("HEAD", { dir = repo, reverse = true, max_count = 2 })
  H.eq(#rev, 2, "log reverse+max_count: two commits")
  H.eq(rev[1].sha, merge, "log reverse+max_count: the limit applies first, then the order flips")
  H.eq(rev[2].sha, c5, "log reverse+max_count: ... oldest of the two first")
  local skipped = git.log("HEAD", { dir = repo, skip = 1, max_count = 1 })
  H.eq(skipped[1].sha, merge, "log skip+max_count: the second newest commit")
  H.eq(#git.log("HEAD", { dir = repo, max_count = 0 }), 0, "log: max_count 0 is no commits")
  local no_merges = git.log("HEAD", { dir = repo, no_merges = true })
  H.eq(#no_merges, 4, "log no_merges: the merge commit is gone")
  local first_parent = git.log("HEAD", { dir = repo, first_parent = true })
  H.eq(#first_parent, 4, "log first_parent: the side branch's commit is skipped")
  H.eq(first_parent[3].sha, c2, "log first_parent: main's own line")
  -- first_parent diffs a merge against its first parent, so the merge HAS files then.
  local fp_files = git.log("HEAD", { dir = repo, first_parent = true, name_status = true })[2].files
  H.eq(#fp_files, 1, "log first_parent+name_status: a merge is diffed against its first parent")
  H.eq(
    fp_files[1].path,
    "side.txt",
    "log first_parent+name_status: ... what the side branch brought"
  )
  H.eq(#git.log("HEAD", { dir = repo, topo_order = true }), 5, "log topo_order: same commits")
  local touching = git.log("HEAD", { dir = repo, paths = { "new.txt" } })
  H.eq(#touching, 1, "log paths: only the commit that touched the path")
  H.eq(touching[1].sha, c2, "log paths: ... c2")
  local empty_range, empty_err = git.log("HEAD..HEAD", { dir = repo })
  H.eq(#empty_range, 0, "log: a range with no commits is {}")
  H.eq(empty_err, nil, "log: ... and no error")

  -- failures are (nil, reason), without a Lua source position
  local unknown, unknown_err = git.log("no-such-revision", { dir = repo })
  H.eq(unknown, nil, "log: an unknown revision is nil")
  no_position(unknown_err, "log unknown revision")

  local opt, opt_err = git.log("--output=" .. repo .. "/x", { dir = repo })
  H.eq(opt, nil, "log: a range that looks like an option is refused")
  H.ok(opt_err and opt_err:find("invalid revision", 1, true), "log: ... naming the reason")
  H.eq(vim.uv.fs_stat(repo .. "/x"), nil, "log: ... and git never saw it (no file written)")
  H.eq(git.log("a\nb", { dir = repo }), nil, "log: a revision with a line break is refused")

  for _, bad_count in ipairs({ -1, 1.5 }) do
    local r, e = git.log("HEAD", { dir = repo, max_count = bad_count })
    H.eq(r, nil, "log: max_count " .. bad_count .. " is refused")
    H.ok(e and e:find("max_count", 1, true), "log: ... naming the option")
  end
  H.eq(git.log("HEAD", { dir = repo, skip = "1" }), nil, "log: skip must be a number")
  H.eq(git.log("HEAD", { dir = repo, paths = { "" } }), nil, "log: an empty path is refused")

  local plain = F.tmpdir("-not-a-repo")
  local not_repo, not_repo_err = git.log("HEAD", { dir = plain })
  H.eq(not_repo, nil, "log: not a repository")
  no_position(not_repo_err, "log not a repository")

  local unborn = F.init("-unborn")
  local none, none_err = git.log("HEAD", { dir = unborn })
  H.eq(none, nil, "log: a repository without commits fails (HEAD does not resolve)")
  no_position(none_err, "log unborn HEAD")

  local missing, missing_err = git.log("HEAD", { dir = repo }, "git-binary-that-does-not-exist")
  H.eq(missing, nil, "log: a missing git binary is a failure, not an error")
  no_position(missing_err, "log missing binary")

  -- A git that is killed by a signal (the OOM killer, a crash) reports exit
  -- status 0 with `signal` set: that must never read as "success" -- an empty
  -- log would mean "no commits", an empty tag list "no tags". POSIX only: a
  -- shell script stands in for git and kills itself.
  if vim.fn.has("win32") == 0 then
    local killer = H.tmpfile(".sh")
    F.write(killer, "#!/bin/sh\nkill -9 $$\n")
    vim.uv.fs_chmod(killer, tonumber("755", 8))
    local probe = git.run({ "log" }, nil, killer)
    if probe.code ~= -1 then -- (a noexec temp directory cannot run the stand-in)
      H.eq(probe.ok, false, "signal: a killed process is not ok")
      H.eq(probe.signal, 9, "signal: ... and the signal is reported")
      H.eq(probe.code, 128 + 9, "signal: ... as 128 + signal, the shell's convention")
      local killed, killed_err = git.log("HEAD", { dir = repo }, killer)
      H.eq(killed, nil, "signal: log is a failure, not an empty history")
      H.ok(
        killed_err and killed_err:find("terminated by signal 9", 1, true),
        "signal: ... and says why: " .. tostring(killed_err)
      )
      local anc, anc_err = git.is_ancestor("a", "b", { dir = repo }, killer)
      H.eq(anc, nil, "signal: is_ancestor does not answer `true` for a killed git")
      H.ok(anc_err and anc_err:find("signal 9", 1, true), "signal: ... it reports the signal")
      H.eq(git.tags({ dir = repo }, killer), nil, "signal: tags is a failure, not `no tags`")
      local async_probe
      git.run_async({ "log" }, nil, function(res)
        async_probe = res
      end, killer)
      wait_for(function()
        return async_probe ~= nil
      end)
      H.eq((async_probe or {}).ok, false, "signal: run_async reports a killed process as failed")
      H.eq((async_probe or {}).signal, 9, "signal: ... with the signal")
    end
    vim.fn.delete(killer)
  end

  -- A process that merely exits with 124 is not a timeout.
  local exits_124 = git.run(
    { "-n", "-i", "NONE", "--headless", "-u", "NONE", "-c", "cquit 124" },
    nil,
    vim.v.progpath
  )
  H.eq(exits_124.code, 124, "timed_out: the exit code is reported")
  H.eq(exits_124.timed_out, false, "timed_out: ... but without a timeout_ms set it is no timeout")

  -- The user's own git config must not change what the parser reads: another
  -- output encoding would hand back invalid UTF-8, `log.showRoot=false` would
  -- hide the files of the root commit. (GIT_CONFIG_COUNT needs git 2.31.)
  local cfg_major, cfg_minor = F.git(repo, { "--version" }):match("(%d+)%.(%d+)")
  if tonumber(cfg_major) > 2 or (tonumber(cfg_major) == 2 and tonumber(cfg_minor) >= 31) then
    local cfg_repo = F.init("-config-robust")
    F.write(cfg_repo .. "/a.txt", "a\n")
    F.commit(cfg_repo, "café au lait", { when = BASE + 10 })
    local hostile_cfg = {
      GIT_CONFIG_COUNT = "2",
      GIT_CONFIG_KEY_0 = "i18n.logOutputEncoding",
      GIT_CONFIG_VALUE_0 = "ISO-8859-1",
      GIT_CONFIG_KEY_1 = "log.showRoot",
      GIT_CONFIG_VALUE_1 = "false",
    }
    local cfg_log = git.log("HEAD", { dir = cfg_repo, name_status = true, env = hostile_cfg })
    H.ok(cfg_log and cfg_log[1], "config: log reads the repository under a hostile user config")
    H.eq((cfg_log or {})[1].subject, "café au lait", "config: output encoding pinned to UTF-8")
    H.eq(#(cfg_log or {})[1].files, 1, "config: the root commit keeps its files (log.showRoot)")
  end

  -- A timeout names itself in the reason (the runner is faked: no waiting).
  H.with_patched(require("lib.nvim.cross.run_argv"), "run_blocking_result", function()
    return { ok = false, code = 124, stdout = "", stderr = "", timed_out = true }
  end, function()
    local r, e = git.log("HEAD", { dir = repo, timeout_ms = 250 })
    H.eq(r, nil, "log timeout: nil")
    H.ok(e and e:find("timed out after 250 ms", 1, true), "log timeout: says so: " .. tostring(e))
  end)

  -- ── log_async ───────────────────────────────────────────────────────────
  local async_entries, async_err, async_done
  local handle = git.log_async("HEAD", { dir = repo, name_status = true }, function(entries, err)
    async_entries, async_err, async_done = entries, err, true
  end)
  H.eq(type(handle.stop), "function", "log_async: returns a stoppable handle")
  H.ok(
    wait_for(function()
      return async_done
    end),
    "log_async: on_done fires"
  )
  H.eq(async_err, nil, "log_async: no error")
  H.eq(#(async_entries or {}), 5, "log_async: the same five commits")
  H.eq((async_entries or {})[4].sha, c2, "log_async: ... in the same order")
  H.eq(#(async_entries or {})[4].files, 3, "log_async: ... with their files")

  local refused_done, refused_err, refused_result = false, nil, "unset"
  git.log_async("--bad", { dir = repo }, function(entries, err)
    refused_done, refused_result, refused_err = true, entries, err
  end)
  H.eq(refused_done, false, "log_async: even a refused range reports asynchronously")
  H.ok(
    wait_for(function()
      return refused_done
    end),
    "log_async: ... and does report"
  )
  H.eq(refused_result, nil, "log_async: a refused range is nil")
  H.ok(
    refused_err and refused_err:find("invalid revision", 1, true),
    "log_async: ... with a reason"
  )

  -- ── a blobless clone: history and file names are readable without blobs ──
  local origin = F.init("-blobless-origin")
  F.git(origin, { "config", "uploadpack.allowFilter", "true" })
  F.write(origin .. "/f.txt", "1\n")
  F.commit(origin, "one", { when = BASE + 100 })
  F.write(origin .. "/f.txt", "2\n")
  F.write(origin .. "/g.txt", "g\n")
  F.commit(origin, "two", { when = BASE + 200 })
  F.write(origin .. "/f.txt", "3\n")
  local origin_tip = F.commit(origin, "three", { when = BASE + 300 })

  local parent = F.tmpdir("-blobless-parent")
  local clone = parent .. "/clone"
  local _, clone_code = F.git(parent, {
    "clone",
    "-q",
    "--filter=blob:none",
    vim.uri_from_fname(origin),
    clone,
  }, { allow_fail = true })
  if clone_code ~= 0 then
    -- On CI a failing file:// clone must fail the spec: skipping it silently
    -- would turn the main use case (a blobless clone) green without testing it.
    H.ok(not vim.env.CI, "fixture: the blobless file:// clone failed on CI")
    io.stdout:write("      (skipped the blobless part: file:// clone failed)\n")
  else
    local partial = F.git(clone, { "config", "remote.origin.partialclonefilter" })
    H.eq(partial, "blob:none", "fixture: the clone is blobless")
    local blobless, blobless_err =
      git.log("HEAD", { dir = clone, name_status = true, no_lazy_fetch = true })
    H.ok(blobless, "log: reads a blobless clone without blobs: " .. tostring(blobless_err))
    blobless = blobless or {}
    H.eq(#blobless, 3, "log blobless: all three commits")
    H.eq(blobless[1].sha, origin_tip, "log blobless: the tip")
    H.eq(#blobless[2].files, 2, "log blobless: the file names of an older commit, no blobs needed")

    -- no_lazy_fetch holds on EVERY git version: GIT_NO_LAZY_FETCH only exists
    -- since 2.44, so the option also blocks the transport. A command that does
    -- need blobs fails instead of fetching them quietly.
    local stat = git.run({ "log", "--stat" }, { dir = clone, no_lazy_fetch = true })
    H.eq(stat.ok, false, "no_lazy_fetch: --stat needs blobs and fails instead of fetching them")
    H.ok(
      stat.stderr and stat.stderr:find("fetch", 1, true),
      "no_lazy_fetch: ... complaining about the object it could not fetch"
    )
    -- ... also where the clone's own (or the user's global) config allows a
    -- transport: a per-protocol `protocol.file.allow=always` beats
    -- `-c protocol.allow=never` but not GIT_ALLOW_PROTOCOL. git < 2.44 is
    -- simulated by switching GIT_NO_LAZY_FETCH off again.
    F.git(clone, { "config", "protocol.file.allow", "always" })
    local old_git = git.run(
      { "log", "--stat" },
      { dir = clone, no_lazy_fetch = true, env = { GIT_NO_LAZY_FETCH = "0" } }
    )
    H.eq(
      old_git.ok,
      false,
      "no_lazy_fetch: holds without GIT_NO_LAZY_FETCH although the clone's config allows the transport"
    )

    -- the same call without the option is allowed to fetch (and, here, does)
    local fetched = git.run({ "log", "--stat" }, { dir = clone })
    H.eq(fetched.ok, true, "control: without no_lazy_fetch git fetches the missing blobs")
  end

  -- ── paths are literal, an order file cannot break the log, hostile dates ──
  local lit = F.init("-literal-paths")
  F.write(lit .. "/a1.txt", "1\n")
  F.commit(lit, "touches a1", { when = 1700000100 })
  F.write(lit .. "/a[1].txt", "1\n")
  F.commit(lit, "touches a[1]", { when = 1700000200 })
  local function subjects(entries)
    local out = {}
    for _, e in ipairs(entries or {}) do
      out[#out + 1] = e.subject
    end
    return table.concat(out, ",")
  end
  H.eq(
    subjects(git.log("HEAD", { dir = lit, paths = { "a[1].txt" } })),
    "touches a[1]",
    "log paths: a path is literal -- a[1].txt is not the glob that matches a1.txt"
  )
  H.eq(
    subjects(git.log("HEAD", { dir = lit, paths = { "*.txt" } })),
    "",
    "log paths: ... and * is not a wildcard"
  )
  H.eq(
    subjects(git.log("HEAD", { dir = lit, paths = { "a[1].txt" }, pathspecs = true })),
    "touches a[1],touches a1",
    "log paths: pathspecs = true asks for git's pathspec semantics (the glob also matches a1.txt)"
  )

  F.git(lit, { "config", "diff.orderFile", "no-such-order-file.txt" })
  local ordered, ordered_err = git.log("HEAD", { dir = lit, name_status = true })
  H.ok(
    ordered,
    "log: a diff.orderFile that does not exist does not break name_status: "
      .. tostring(ordered_err)
  )
  H.eq(#(ordered or {}), 2, "log: ... and both commits come back")

  -- a commit object with a committer date of 400 digits (git accepts it unless
  -- fsckObjects is on): `tonumber` would make it `inf`
  local tree = F.git(lit, { "rev-parse", "HEAD^{tree}" })
  local raw_commit = ("tree %s\nauthor T <t@x.y> %s +0000\ncommitter T <t@x.y> %s +0000\n\nhuge date\n"):format(
    tree,
    ("9"):rep(400),
    ("9"):rep(400)
  )
  local made = vim
    .system(
      { "git", "-C", lit, "hash-object", "-t", "commit", "-w", "--literally", "--stdin" },
      { stdin = raw_commit, text = true }
    )
    :wait()
  if made.code == 0 then
    F.git(lit, { "update-ref", "refs/heads/huge-date", vim.trim(made.stdout) })
    local huge = git.log("huge-date", { dir = lit, max_count = 1 })
    H.ok(huge and huge[1], "log: a commit with a 400-digit date is listed")
    H.eq((huge or { {} })[1].commit_time, nil, "log: ... its date is nil, not inf")
    H.eq((huge or { {} })[1].author_time, nil, "log: ... also the author date")
  end

  -- ── an inherited pathspec switch cannot change what `paths` means ──────────
  do
    local ps = F.init("-pathspec-env")
    F.write(ps .. "/Ab.txt", "1\n")
    F.commit(ps, "touches Ab", { when = 1700000100 })
    F.write(ps .. "/aB.txt", "1\n")
    F.commit(ps, "touches aB", { when = 1700000200 })
    local saved_lit, saved_icase = vim.env.GIT_LITERAL_PATHSPECS, vim.env.GIT_ICASE_PATHSPECS
    vim.env.GIT_LITERAL_PATHSPECS, vim.env.GIT_ICASE_PATHSPECS = "1", "1"
    -- (without `no_lazy_fetch`: the reset does not depend on it)
    local only = git.log("HEAD", { dir = ps, paths = { "Ab.txt" } })
    vim.env.GIT_LITERAL_PATHSPECS, vim.env.GIT_ICASE_PATHSPECS = saved_lit, saved_icase
    H.ok(only ~= nil, "log paths: LITERAL+ICASE in the env is not a fatal 'incompatible settings'")
    H.eq(#(only or {}), 1, "log paths: GIT_LITERAL/ICASE_PATHSPECS in the env are overridden")
    H.eq((only or { {} })[1].subject, "touches Ab", "log paths: ... exact case")

    -- NOGLOB in the env must not break a caller's own pathspec magic
    local saved_noglob = vim.env.GIT_NOGLOB_PATHSPECS
    vim.env.GIT_NOGLOB_PATHSPECS = "1"
    local globbed = git.log("HEAD", { dir = ps, paths = { "A*.txt" }, pathspecs = true })
    vim.env.GIT_NOGLOB_PATHSPECS = saved_noglob
    H.ok(
      #(globbed or {}) >= 1,
      "log paths: GIT_NOGLOB_PATHSPECS in the env does not disable a glob"
    )
  end

  -- ── max_output_bytes: one huge message cannot fill the editor's memory ─────
  local fat = F.init("-fat-message")
  F.write(fat .. "/f.txt", "1\n")
  F.commit(fat, "big\n\n" .. ("y"):rep(20000), { when = 1700000100 })
  local capped = git.run({ "log", "-1", "--format=%B" }, { dir = fat, max_output_bytes = 1000 })
  H.eq(capped.ok, false, "run max_output_bytes: output past the cap is a failure")
  H.eq(capped.code, 125, "run max_output_bytes: ... with the output-limit code")
  H.ok(#capped.stdout <= 1000, "run max_output_bytes: ... stdout is cut at the cap")
  H.ok(
    capped.stderr:find("exceeded", 1, true) ~= nil,
    "run max_output_bytes: ... and the reason is in stderr"
  )
  local capped_async_err
  git.log_async("HEAD", { dir = fat, max_output_bytes = 1000 }, function(_, err)
    capped_async_err = err
  end)
  vim.wait(20000, function()
    return capped_async_err ~= nil
  end, 10)
  H.ok(
    capped_async_err and capped_async_err:find("exceeded", 1, true) ~= nil,
    "log_async max_output_bytes: the error names the output limit, not a signal"
  )
  local capped_log, capped_log_err = git.log("HEAD", { dir = fat, max_output_bytes = 1000 })
  H.eq(
    capped_log,
    nil,
    "log max_output_bytes: a log past the cap is an error, not a truncated list"
  )
  H.ok(capped_log_err and capped_log_err ~= "", "log max_output_bytes: ... with a reason")
  local roomy = git.log("HEAD", { dir = fat, max_output_bytes = 1024 * 1024 })
  H.eq(#(roomy or {}), 1, "log max_output_bytes: under the cap nothing changes")

  F.cleanup()
end
