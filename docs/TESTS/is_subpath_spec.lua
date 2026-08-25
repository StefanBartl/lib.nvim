-- docs/TESTS/is_subpath_spec.lua — lib.nvim.fs.is_subpath
--
-- Two contracts: the prefix semantics themselves (whole segments only, both
-- separators, equality included) and the opt-in `opts` canonicalization that
-- makes a comparison survive two differently-spelled spellings of the same
-- directory — a Windows drive-letter case mismatch, an 8.3 short name, a
-- symlinked temp dir on macOS.

return function(H)
  local eq, ok = H.eq, H.ok

  local is_subpath = require("lib.nvim.fs.is_subpath")
  local normkey = require("lib.nvim.fs.normkey")

  -- --------------------------------------------------------------- surface

  eq(type(is_subpath), "function", "is_subpath: module is a function")
  eq(require("lib").is_subpath, is_subpath, "is_subpath: reachable as lib.is_subpath")

  -- ------------------------------------------------------ prefix semantics

  ok(is_subpath("/foo/bar", "/foo"), "is_subpath: direct child")
  ok(is_subpath("/foo/bar/baz.lua", "/foo"), "is_subpath: nested descendant")
  ok(is_subpath("/foo", "/foo"), "is_subpath: equality counts as inside")
  ok(is_subpath("/foo/bar", "/foo/"), "is_subpath: trailing slash on base")

  eq(is_subpath("/foo", "/foo/bar"), false, "is_subpath: parent is not inside child")
  eq(is_subpath("/foobar", "/foo"), false, "is_subpath: only whole segments count")
  eq(is_subpath("/other/foo", "/foo"), false, "is_subpath: unrelated path")

  -- `vim.fs.normalize` folds "\\" to "/" only where the backslash is a
  -- separator, i.e. on Windows -- on Linux it is a legal filename character and
  -- stays put, so this is a Windows-only contract. It is also the regression
  -- the module was fixed for: appending the *native* separator to `base` never
  -- matched the forward-slash-normalized `path`.
  if vim.fn.has("win32") == 1 then
    local bs = string.char(92)
    ok(
      is_subpath("C:" .. bs .. "foo" .. bs .. "bar", "C:" .. bs .. "foo"),
      "is_subpath: backslash input"
    )
    ok(is_subpath("C:" .. bs .. "foo" .. bs .. "bar", "C:/foo"), "is_subpath: mixed separators")
  end

  -- ------------------------------------------------------------------ opts

  -- Cheap mode: no filesystem access at all, so a path that does not exist is
  -- still answered on its spelling alone, with duplicate separators collapsed.
  ok(
    is_subpath("/no/such/dir//child", "/no/such/dir", { realpath = false }),
    "is_subpath: realpath=false collapses duplicate separators without a syscall"
  )
  eq(
    is_subpath("/no/such/dir", "/no/such/dir/child", { realpath = false }),
    false,
    "is_subpath: realpath=false keeps the prefix semantics"
  )

  -- The case opts exist for: the OS hands back a spelling of a directory that
  -- is not its canonical one -- an 8.3 short name on Windows (`STEFAN~1`),
  -- `/var` -> `/private/var` on macOS. `vim.fs.normalize` cannot know; only a
  -- `uv.fs_realpath` can. Both sides of a real comparison rarely come from the
  -- same source, so this is not hypothetical.
  local uv = vim.uv or vim.loop
  local tmpdir = vim.fn.fnamemodify(vim.fn.tempname(), ":h")
  vim.fn.mkdir(tmpdir, "p")
  local child = tmpdir .. "/is_subpath_spec_child"
  vim.fn.mkdir(child, "p")

  ok(is_subpath(child, tmpdir, {}), "is_subpath: real temp child, opts default realpath")
  ok(is_subpath(child, tmpdir, { realpath = true }), "is_subpath: real temp child, explicit")
  eq(is_subpath(tmpdir, child, {}), false, "is_subpath: parent temp dir is not inside child")

  local canonical = uv.fs_realpath(tmpdir)
  if canonical and vim.fs.normalize(canonical) ~= vim.fs.normalize(tmpdir) then
    -- Only assert the difference where this host actually produces two
    -- spellings; on a Linux CI runner tempname() is already canonical and
    -- there is nothing for realpath to resolve.
    eq(
      is_subpath(child, canonical),
      false,
      "is_subpath: two spellings of the same dir compare false without opts"
    )
    ok(
      is_subpath(child, canonical, {}),
      "is_subpath: opts resolve the two spellings to the same dir"
    )
  end

  ok(
    is_subpath(normkey(child), normkey(tmpdir)),
    "is_subpath: pre-normkeyed arguments agree without opts"
  )

  vim.fn.delete(child, "rf")
end
