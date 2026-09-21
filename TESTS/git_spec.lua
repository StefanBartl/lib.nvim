-- TESTS/git_spec.lua — lib.nvim.git
--
-- Covers `M.info(dir)` only, the one function this module gained alongside
-- runtime-analysis.telemetry's `info` field (which tags a report with the
-- branch/version of the plugin it was collected from). The other ten
-- functions predate this spec file and are read-cwd helpers for editor
-- features (autocommands, status integrations) — real, but not part of
-- this pass; `M.info` is the one worth a real assertion here because it is
-- the one a consumer plugin calls programmatically against an arbitrary
-- directory, not just from inside this editor session.

return function(H)
  local git = require("lib.nvim.git")

  -- This repository's own checkout is a real git repo — no fixture needed
  -- for the positive case, and no git state is mutated by any of these
  -- reads.
  local root = vim.fn.getcwd()
  local info = git.info(root)

  H.ok(type(info) == "table", "git.info: always returns a table, never nil")
  H.ok(
    info.branch == nil or type(info.branch) == "string",
    "git.info: branch is a string or nil (detached HEAD), never anything else"
  )
  H.ok(
    info.version ~= nil,
    "git.info: version answers something for a repo with at least one commit (a tag, or --always's short hash fallback)"
  )
  H.ok(
    info.commit == nil or (type(info.commit) == "string" and #info.commit > 0),
    "git.info: commit is a non-empty short hash or nil"
  )

  -- A directory that exists but is not a git repo at all: every field nil,
  -- not a guessed placeholder and not an error.
  local non_repo = vim.fn.tempname() .. "-not-a-repo"
  vim.fn.mkdir(non_repo, "p")
  local outside = git.info(non_repo)
  H.eq(outside.branch, nil, "git.info: outside any repo, branch is nil")
  H.eq(outside.version, nil, "git.info: ...version is nil too, not a fabricated one")
  H.eq(outside.commit, nil, "git.info: ...and commit")
  vim.fn.delete(non_repo, "rf")

  -- A nonexistent directory: `git -C <dir>` fails to even start; still no
  -- error, still every field nil.
  local ok, missing_info = pcall(git.info, non_repo .. "-still-does-not-exist")
  H.eq(ok, true, "git.info: a nonexistent directory does not raise")
  H.eq(missing_info.branch, nil, "git.info: ...and every field is nil")
  -- ── M.refs ────────────────────────────────────────────────────────────
  --
  -- This checkout has branches but (today) no tags, so the tag group is
  -- asserted only through the group toggles, not through a fixture.
  local refs = git.refs(root)
  H.ok(type(refs) == "table" and #refs > 0, "git.refs: this repo has named revisions")
  H.ok(
    vim.tbl_contains(refs, "main"),
    "git.refs: a local branch is offered bare, exactly as git accepts it as a revision"
  )

  local seen = {}
  local unique = true
  for _, r in ipairs(refs) do
    if seen[r] then
      unique = false
    end
    seen[r] = true
  end
  H.ok(unique, "git.refs: deduplicated")

  -- Remote branches keep their prefix; stripping it would collide with the
  -- identically named local branch and produce a candidate git cannot
  -- disambiguate.
  local has_remote = false
  for _, r in ipairs(refs) do
    if r:match("^origin/") then
      has_remote = true
    end
  end
  H.ok(has_remote, "git.refs: remote branches keep their remote prefix")

  H.eq(#git.refs(root, { limit = 2 }), 2, "git.refs: limit caps the total")
  H.ok(
    #git.refs(root, { remotes = false, tags = false }) < #refs,
    "git.refs: group toggles actually narrow the list"
  )
  for _, r in ipairs(git.refs(root, { branches = false, tags = false })) do
    H.ok(r:match("/") ~= nil, "git.refs: remotes-only yields only prefixed refs (" .. r .. ")")
  end

  -- Same fail-quiet stance as `info`: not a repo -> empty list, not an error
  -- and not nil, so a completion callback can return it directly.
  local no_repo = vim.fn.tempname() .. "-not-a-repo-either"
  vim.fn.mkdir(no_repo, "p")
  H.eq(#git.refs(no_repo), 0, "git.refs: outside any repo, an empty list")
  vim.fn.delete(no_repo, "rf")
  H.eq(#git.refs(no_repo .. "/gone"), 0, "git.refs: nonexistent directory, an empty list")

  -- ── M.blame_porcelain ────────────────────────────────────────────────
  --
  -- README.md is tracked and has real history in this repo -- no fixture
  -- needed. The porcelain parser's whole job is filling in metadata for
  -- repeated commits from a per-sha cache (git only emits the full author/
  -- summary block the first time a commit is mentioned) -- that is what the
  -- "every entry has an author" assertion below actually exercises, not
  -- just "the call did not error".
  local blame = git.blame_porcelain("README.md", { dir = root })
  H.ok(type(blame) == "table", "git.blame_porcelain: returns a table for a tracked file")
  H.ok(#blame > 0, "git.blame_porcelain: README.md has at least one line")
  for _, entry in ipairs(blame) do
    H.ok(type(entry.line) == "number" and entry.line > 0, "blame entry: line is a positive number")
    H.ok(type(entry.sha) == "string" and #entry.sha > 0, "blame entry: sha is a non-empty string")
    H.ok(
      entry.author == nil or type(entry.author) == "string",
      "blame entry: author is a string or nil, never anything else"
    )
    H.ok(
      type(entry.author) == "string" and #entry.author > 0,
      "blame entry: metadata is filled in even for a line whose commit repeats (cache hit)"
    )
  end

  -- Line numbers are exactly 1..N, in order, one entry per line — not just
  -- "some entries came back".
  local expected_line_count = #vim.fn.readfile(root .. "/README.md")
  H.eq(#blame, expected_line_count, "git.blame_porcelain: one entry per line in the file")
  for idx, entry in ipairs(blame) do
    H.eq(entry.line, idx, "git.blame_porcelain: entries are in file order, 1-based")
  end

  -- A line-range restricts the output to exactly that range.
  local ranged = git.blame_porcelain("README.md", { dir = root, first = 1, last = 3 })
  H.eq(#ranged, 3, "git.blame_porcelain: first/last restricts to the requested range")
  H.eq(ranged[1].line, 1, "git.blame_porcelain: ranged output keeps real file line numbers")

  -- A file that exists but was never committed: git blame fails (not a
  -- crash, not a fabricated empty-but-ok result) -- distinguishable from
  -- "tracked file with zero lines" (ERR-10/ERR-11).
  local untracked = root .. "/__lib_nvim_blame_spec_scratch.md"
  vim.fn.writefile({ "scratch" }, untracked)
  local no_blame, err = git.blame_porcelain("__lib_nvim_blame_spec_scratch.md", { dir = root })
  H.eq(no_blame, nil, "git.blame_porcelain: an untracked file is a real failure, not an empty list")
  H.ok(type(err) == "string" and #err > 0, "git.blame_porcelain: ...and says why")
  vim.fn.delete(untracked)

  -- Outside any repo entirely: same failure shape, not a raise.
  local outside_dir = vim.fn.tempname() .. "-not-a-repo-blame"
  vim.fn.mkdir(outside_dir, "p")
  local ok_call, outside_blame = pcall(git.blame_porcelain, "whatever.md", { dir = outside_dir })
  H.eq(ok_call, true, "git.blame_porcelain: outside a repo does not raise")
  H.eq(outside_blame, nil, "git.blame_porcelain: ...and reports failure, not an empty table")
  vim.fn.delete(outside_dir, "rf")
end
