-- TESTS/globbable_spec.lua — lib.nvim.fs.globbable
--
-- The contract is narrow on purpose: hand back a spelling of the directory
-- that `vim.fn.glob` can read as a path rather than as a pattern. The one
-- case that matters is the tilde — on Windows `%TEMP%` is the 8.3 short form
-- (`C:/Users/STEFAN~1/...`) for any profile name over eight characters, and
-- glob reads `~1` as a home-directory reference for a user that does not
-- exist, then returns an empty list without an error.
--
-- The last block is the one worth keeping: it does not test the helper's
-- return value at all, it globs a real tree twice and asserts the counts
-- agree. That is the actual bug, and it is the assertion that would have
-- caught it.

return function(H)
  local eq, ok = H.eq, H.ok

  local globbable = require("lib.nvim.fs.globbable")
  local uv = vim.uv or vim.loop

  -- --------------------------------------------------------------- surface

  eq(type(globbable), "function", "globbable: module is a function")
  eq(globbable(""), "", "globbable: empty string in, empty string out")
  eq(globbable(nil), "", "globbable: non-string in, empty string out")

  -- ------------------------------------------------------- the no-op path

  -- No tilde means nothing to resolve, and the input must come back
  -- untouched: glob's caller expects results spelled like the root it passed.
  local cwd = vim.fn.getcwd():gsub("\\", "/")
  eq(globbable(cwd), cwd, "globbable: a path without a tilde is returned verbatim")
  eq(
    globbable("relative/dir"),
    "relative/dir",
    "globbable: a relative path without a tilde is untouched"
  )

  -- A path that does not exist cannot be resolved, and is left alone —
  -- globbing it finds nothing either way, so there is nothing to repair.
  local missing = cwd .. "/definitely~1/not/here"
  eq(globbable(missing), missing, "globbable: an unresolvable path is returned unchanged")

  -- ------------------------------------------------ the resolving path

  -- $TEMP is the short form on Windows and a plain path elsewhere, so this
  -- asserts the same property on every platform: whatever comes back must be
  -- the same directory, and must carry no tilde if the OS can resolve one.
  local tmp = (vim.env.TEMP or vim.env.TMPDIR or vim.env.TMP or "/tmp"):gsub("\\", "/")
  local resolved = globbable(tmp)

  ok(uv.fs_stat(resolved) ~= nil, "globbable: the resolved temp root still exists")
  if tmp:find("~", 1, true) then
    ok(not resolved:find("~", 1, true), "globbable: the tilde is resolved away")
  end

  -- -------------------------------------------- the regression it exists for

  -- Build a small tree under the temp root and glob it twice: once through
  -- the raw spelling the environment handed us, once through globbable. On a
  -- platform where $TEMP is already the long form the two are trivially
  -- equal; on Windows the raw one returns zero and only the second finds the
  -- files. Either way the assertion is the same sentence: globbable's
  -- spelling finds what is there.
  local base = vim.fn.tempname()
  vim.fn.mkdir(base .. "/nested", "p")
  vim.fn.writefile({ "one" }, base .. "/a.txt")
  vim.fn.writefile({ "two" }, base .. "/nested/b.txt")

  local found = vim.fn.globpath(globbable(base:gsub("\\", "/")), "**/*.txt", false, true)
  eq(#found, 2, "globbable: globbing through it finds both files in the tree")

  vim.fn.delete(base, "rf")
end
