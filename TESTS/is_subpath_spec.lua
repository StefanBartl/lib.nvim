-- TESTS/is_subpath_spec.lua — lib.nvim.fs.is_subpath
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

  -- `ignore_case`: a file system that ignores case (Windows) names one folder in many spellings.
  local fold = { realpath = false, ignore_case = true }
  ok(is_subpath("c:/a/b/x.lua", "C:/A/B", fold), "is_subpath: ignore_case, child")
  ok(is_subpath("C:/A/B", "c:/a/b", fold), "is_subpath: ignore_case, equality")
  eq(is_subpath("C:/A/BC/x", "c:/a/b", fold), false, "is_subpath: ignore_case keeps whole segments")
  eq(
    is_subpath("C:/A", "c:/a/b", fold),
    false,
    "is_subpath: ignore_case, parent is not inside child"
  )
  ok(
    is_subpath("/", "/", fold) and is_subpath("/x", "/", fold),
    "is_subpath: ignore_case, POSIX root"
  )
  ok(is_subpath("C:/x", "C:/", fold), "is_subpath: ignore_case, drive root")
  ok(is_subpath("C:/a/b/c/d.lua", "C:/a/b/", fold), "is_subpath: ignore_case, trailing slash")
  eq(
    is_subpath("/Foo/x", "/foo", { realpath = false }),
    false,
    "is_subpath: case counts by default"
  )
  -- the fold does not depend on the `realpath` setting: it works with the default (true) and with an explicit one
  ok(
    is_subpath("/Nope-Zz/A/x.lua", "/nope-zz/a", { ignore_case = true }),
    "is_subpath: ignore_case, default realpath"
  )
  ok(
    is_subpath("/Nope-Zz/A/x.lua", "/nope-zz/a", { realpath = true, ignore_case = true }),
    "is_subpath: ignore_case, explicit realpath"
  )
  ok(
    not is_subpath("/Nope-Zz/A/x.lua", "/nope-zz/a", { realpath = true }),
    "is_subpath: case counts without ignore_case, with realpath"
  )

  -- `string.lower` folds ASCII only; `Ärger` / `ärger` are one folder on NTFS/APFS, and a deny-list
  -- ("is this path inside the forbidden folder") must not be bypassed by spelling it with another
  -- non-ASCII case.
  ok(is_subpath("C:/t/ärger/x.md", "C:/t/Ärger", fold), "is_subpath: ignore_case folds non-ASCII")
  ok(is_subpath("C:/t/ÄRGER", "C:/t/ärger", fold), "is_subpath: ignore_case, non-ASCII equality")
  eq(
    is_subpath("C:/t/Ärgerx/y", "C:/t/ärger", fold),
    false,
    "is_subpath: ignore_case non-ASCII keeps whole segments"
  )
  eq(
    is_subpath("/t/Ärger/x", "/t/ärger", { realpath = false }),
    false,
    "is_subpath: non-ASCII case still counts by default"
  )

  -- A trailing separator is no different spelling of the same directory: the no-`opts` branch gets
  -- that from `vim.fs.normalize`, and the `normkey` branch must agree (the drop-in for the old
  -- `fsio.is_inside`, which normalized both sides first).
  ok(is_subpath("/v", "/v/", fold), "is_subpath: ignore_case, equality with a trailing-slash base")
  ok(is_subpath("C:/x", "C:/x/", fold), "is_subpath: ignore_case, drive path with trailing slash")
  ok(is_subpath("/v", "/v//", fold), "is_subpath: ignore_case, several trailing slashes")
  ok(is_subpath("/v/", "/v", fold), "is_subpath: ignore_case, trailing slash on path")
  ok(is_subpath("C:/", "C:/", fold), "is_subpath: ignore_case, a drive root keeps its slash")
  ok(is_subpath("/", "/", fold), "is_subpath: ignore_case, the POSIX root keeps its slash")
  -- "C:" is "the cwd on drive C", not the drive root: stripping the slash off `C:/` must not make
  -- the two compare equal.
  eq(
    is_subpath("C:", "C:/", fold),
    false,
    "is_subpath: ignore_case, a bare drive is not the drive root"
  )
  eq(
    is_subpath("/vv", "/v/", fold),
    false,
    "is_subpath: ignore_case, trailing-slash base keeps whole segments"
  )
  eq(
    is_subpath("/v/", "/v/a", fold),
    false,
    "is_subpath: ignore_case, a parent is not inside a trailing-slash child"
  )
  ok(
    is_subpath("/v", "/v/", { realpath = false }),
    "is_subpath: realpath=false, equality with a trailing-slash base"
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
