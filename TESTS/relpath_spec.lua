-- TESTS/relpath_spec.lua — lib.nvim.fs.relpath
--
-- No prior coverage existed for this module at all. It is a pure string
-- transform, but goes through `vim.fn.fnamemodify(..., ":p")` first, whose
-- absolute-path handling is platform-dependent enough (it injects a drive
-- prefix for some bare POSIX-shaped inputs on native Windows, inconsistently
-- across otherwise-similar strings) that fabricated paths are not reliable
-- test fixtures here. Every case below is anchored on the real repo root
-- (`vim.fn.getcwd()`), which `fnamemodify(":p")` always returns unchanged.
--
-- BUG: root_of() compared Windows drive letters with plain `~=`, which is
-- case-sensitive -- "c:" and "C:" name the SAME drive on Windows, but the
-- function treated them as different roots and silently fell back to
-- returning the absolute `path` unchanged instead of a real relative path.
-- Confirmed against the pre-fix code on a real repo path: relpath with a
-- lowercase-drive `path` against an uppercase-drive `base` (both otherwise
-- identical) returned the whole absolute path instead of "TESTS/harness.lua".
-- The fix folds only the drive-letter prefix through the same
-- `lib.nvim.cross.fs.separators.drive_upper` helper `lib.nvim.fs.normkey`
-- already uses for exactly this reason, leaving every other character's
-- case (including the rest of the returned path) untouched.

return function(H)
  local eq = H.eq

  local relpath = require("lib.nvim.fs.relpath")

  -- --------------------------------------------------------------- surface
  eq(type(relpath), "function", "relpath: module is a function")

  local cwd = vim.fn.getcwd():gsub("\\", "/")
  local parent = vim.fs.dirname(cwd)

  -- ------------------------------------------------------- cross-platform
  eq(relpath(cwd, cwd), ".", "relpath: identical paths yield '.'")
  eq(relpath(cwd .. "/TESTS/harness.lua", cwd), "TESTS/harness.lua", "relpath: direct descendant")
  eq(relpath(cwd .. "/TESTS", cwd .. "/lua"), "../TESTS", "relpath: sibling directory")
  eq(relpath(parent, cwd), "..", "relpath: climbing to a pure ancestor, no descent back down")
  eq(
    relpath(cwd .. "/TESTS/", cwd .. "/"),
    "TESTS",
    "relpath: trailing separators on either side are ignored"
  )

  -- ------------------------------------------------------------- Windows
  if vim.fn.has("win32") == 1 then
    -- Mixed separators: a fully backslashed input still normalizes.
    local backslashed = cwd:gsub("/", "\\") .. "\\TESTS\\harness.lua"
    eq(
      relpath(backslashed, cwd),
      "TESTS/harness.lua",
      "relpath: backslash input is normalized to forward slashes"
    )

    local lower_drive_cwd = cwd:sub(1, 1):lower() .. cwd:sub(2)
    local upper_drive_cwd = cwd:sub(1, 1):upper() .. cwd:sub(2)

    -- BUG regression: a case-differing drive letter is still the same drive.
    eq(
      relpath(lower_drive_cwd .. "/TESTS/harness.lua", upper_drive_cwd),
      "TESTS/harness.lua",
      "relpath: BUG regression -- lowercase path drive vs uppercase base drive is still one relative path"
    )
    eq(
      relpath(upper_drive_cwd .. "/TESTS/harness.lua", lower_drive_cwd),
      "TESTS/harness.lua",
      "relpath: BUG regression -- uppercase path drive vs lowercase base drive is still one relative path"
    )

    -- Genuinely different drives: no relative path exists, so the absolute
    -- `path` is handed back unchanged.
    local other_drive = (cwd:sub(1, 1):upper() == "D") and "C" or "D"
    local other = other_drive .. cwd:sub(2) .. "/other/file.lua"
    eq(
      relpath(other, cwd),
      other,
      "relpath: a genuinely different drive returns the absolute path unchanged"
    )
  end
end
