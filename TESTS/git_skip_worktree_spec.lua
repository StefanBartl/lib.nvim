-- TESTS/git_skip_worktree_spec.lua — lib.nvim.git.is_skip_worktree / set_skip_worktree / toggle_skip_worktree
--
-- Real throwaway repositories, never string mocks: what is pinned is git's own answer (`ls-files -v`) and
-- that a marked file really stops showing up as modified.

return function(H)
  local git = require("lib.nvim.git")
  local dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
  local F = dofile(dir .. "git_fixture.lua")(H)

  local repo = F.init("-skip-worktree")
  F.write(repo .. "/session.vim", "one\n")
  F.write(repo .. "/other.txt", "x\n")
  F.commit(repo, "base")
  local opts = { dir = repo }

  local function porcelain()
    local out = F.git(repo, { "status", "--porcelain" })
    return out
  end

  -- initial state: tracked, not marked
  H.eq(
    git.is_skip_worktree("session.vim", opts),
    false,
    "is_skip_worktree: a tracked file is not marked"
  )

  -- mark it: a local modification no longer shows
  H.eq(select(1, git.set_skip_worktree("session.vim", true, opts)), true, "set_skip_worktree: on")
  H.eq(git.is_skip_worktree("session.vim", opts), true, "is_skip_worktree: ... marked now")
  -- a different SIZE, not just different bytes: with the same size in the same second git can take the
  -- file for unchanged (racy git), and "... and git status reports the modification" below was a coin flip
  F.write(repo .. "/session.vim", "two, and longer than one\n")
  H.eq(porcelain(), "", "a modified skip-worktree file is not reported by git status")
  H.eq(git.is_dirty(opts), false, "... so the repository is not dirty")

  -- the mark of another file is independent
  H.eq(
    git.is_skip_worktree("other.txt", opts),
    false,
    "is_skip_worktree: other files stay unmarked"
  )

  -- unmark: the modification shows again
  H.eq(select(1, git.set_skip_worktree("session.vim", false, opts)), true, "set_skip_worktree: off")
  H.eq(git.is_skip_worktree("session.vim", opts), false, "is_skip_worktree: ... unmarked again")
  H.ok(
    porcelain():find("session.vim", 1, true) ~= nil,
    "... and git status reports the modification"
  )

  -- toggle returns the state AFTER the flip
  H.eq(git.toggle_skip_worktree("session.vim", opts), true, "toggle: unmarked -> marked")
  H.eq(git.is_skip_worktree("session.vim", opts), true, "toggle: ... and git agrees")
  H.eq(git.toggle_skip_worktree("session.vim", opts), false, "toggle: marked -> unmarked")
  H.eq(git.is_skip_worktree("session.vim", opts), false, "toggle: ... and git agrees")

  -- an absolute path works too
  H.eq(
    git.toggle_skip_worktree(repo .. "/session.vim", opts),
    true,
    "toggle: an absolute path is accepted"
  )
  git.set_skip_worktree("session.vim", false, opts)

  -- also marked assume-unchanged: ls-files tags it lower-case `s`
  -- (two calls: in one `update-index` call the second flag replaces the first)
  F.git(repo, { "update-index", "--skip-worktree", "--", "session.vim" })
  F.git(repo, { "update-index", "--assume-unchanged", "--", "session.vim" })
  H.eq(
    git.is_skip_worktree("session.vim", opts),
    true,
    "is_skip_worktree: skip-worktree plus assume-unchanged still counts"
  )
  F.git(
    repo,
    { "update-index", "--no-skip-worktree", "--no-assume-unchanged", "--", "session.vim" }
  )

  -- failures name themselves: untracked, unknown path, invalid path, not a repository
  F.write(repo .. "/untracked.txt", "u\n")
  local state, err = git.is_skip_worktree("untracked.txt", opts)
  H.eq(state, nil, "is_skip_worktree: an untracked file is unknown, not false")
  H.ok(
    type(err) == "string" and err:find("not tracked", 1, true) ~= nil,
    "... and says so: " .. tostring(err)
  )
  H.eq(
    (git.toggle_skip_worktree("untracked.txt", opts)),
    nil,
    "toggle: an untracked file is an error"
  )

  local ok_missing, err_missing = git.set_skip_worktree("no-such-file", true, opts)
  H.eq(ok_missing, false, "set_skip_worktree: an unknown path is an error")
  H.ok(type(err_missing) == "string" and err_missing ~= "", "... with git's reason")

  for _, bad in ipairs({ "", 42, "a\nb" }) do
    local s, e = git.is_skip_worktree(bad, opts)
    H.eq(s, nil, "is_skip_worktree: invalid path " .. vim.inspect(bad))
    H.ok(
      type(e) == "string" and e:find("invalid path", 1, true) ~= nil,
      "... is refused: " .. tostring(e)
    )
    local ok_set = git.set_skip_worktree(bad, true, opts)
    H.eq(ok_set, false, "set_skip_worktree: invalid path " .. vim.inspect(bad) .. " is refused")
  end

  -- a path is a file name, not a pathspec: no glob, no pathspec magic, and one file only
  F.write(repo .. "/sub/inner.vim", "i\n")
  F.commit(repo, "sub")
  local gstate, gerr = git.is_skip_worktree("*.vim", opts)
  H.eq(gstate, nil, "is_skip_worktree: a glob is not expanded")
  H.ok(
    type(gerr) == "string" and gerr:find("not tracked", 1, true) ~= nil,
    "... it is a name nobody tracks: " .. tostring(gerr)
  )
  local dstate, derr = git.is_skip_worktree("sub", opts)
  H.ok(
    dstate == nil and type(derr) == "string",
    "is_skip_worktree: a directory has no single state"
  )
  H.eq(
    (git.is_skip_worktree(":(top)other.txt", opts)),
    nil,
    "is_skip_worktree: pathspec magic is part of the name"
  )

  -- a leading dash is a file name, not an option (the path comes after `--`)
  F.write(repo .. "/-weird", "w\n")
  F.git(repo, { "add", "--", "-weird" })
  H.eq(git.toggle_skip_worktree("-weird", opts), true, "toggle: a file named like an option")
  H.eq(git.is_skip_worktree("-weird", opts), true, "is_skip_worktree: ... reads back")

  local outside = F.tmpdir("-not-a-repo")
  local o_state, o_err = git.is_skip_worktree("x", { dir = outside })
  H.eq(o_state, nil, "is_skip_worktree: outside a repository is unknown")
  H.ok(type(o_err) == "string" and o_err ~= "", "... with a reason")

  F.cleanup()
end
