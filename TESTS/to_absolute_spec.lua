-- TESTS/to_absolute_spec.lua — lib.nvim.cross.fs.to_absolute
--
-- The contract this exists for: a path made up of nothing but separator
-- characters ("//", "\\\\", "\\/\\", any length or mix) must resolve to
-- exactly the same absolute path as a single separator -- the filesystem
-- root, never the cwd. A naive trailing-separator strip collapses such a
-- string to "" first (which fnamemodify resolves to the cwd, not the
-- root), and on POSIX a literal "\" is just an ordinary filename
-- character, so an un-collapsed backslash-heavy input resolves relative to
-- the cwd rather than to the root either way. Ported from the regression
-- gitsuite.nvim's own dashboard/repos.lua hit (its local, pre-lib.nvim
-- version of this same idea) -- centralized here so every consumer shares
-- one tested implementation instead of re-deriving it.

return function(H)
  local eq, ok = H.eq, H.ok

  local to_absolute = require("lib.nvim.cross.fs.to_absolute")

  eq(type(to_absolute), "function", "to_absolute: module is a function")

  -- --------------------------------------------------------- separator-only

  local root = to_absolute("/")
  local cwd = to_absolute(vim.fn.getcwd())

  ok(root ~= cwd, "to_absolute: a bare '/' must not resolve to the cwd")

  for _, variant in ipairs({ "//", "///", "\\\\", "\\/\\" }) do
    eq(
      to_absolute(variant),
      root,
      ("%q must resolve exactly like a single separator"):format(variant)
    )
    ok(to_absolute(variant) ~= cwd, ("%q must not silently resolve to the cwd"):format(variant))
  end

  -- ------------------------------------------------------- mixed separators

  -- A path spelled with backslashes must resolve to the same absolute path
  -- as its forward-slash spelling, regardless of host OS -- the whole point
  -- of unifying separators before, not after, fnamemodify ever sees them.
  local tmp = vim.fn.fnamemodify(vim.fn.tempname(), ":h")
  local fwd = to_absolute(tmp .. "/some/nested/dir")
  local back = to_absolute((tmp .. "/some/nested/dir"):gsub("/", "\\"))
  eq(back, fwd, "to_absolute: backslash spelling resolves the same as forward-slash spelling")

  -- --------------------------------------------------------------- ordinary

  ok(
    to_absolute("~"):match("^%a?:?[/\\]") ~= nil or to_absolute("~"):sub(1, 1) == "/",
    "to_absolute: '~' expands to an absolute path"
  )
  eq(
    to_absolute("/foo/bar/"),
    to_absolute("/foo/bar"),
    "to_absolute: a trailing separator is dropped"
  )
  eq(
    to_absolute("/foo//bar"),
    to_absolute("/foo/bar"),
    "to_absolute: an internal separator run collapses"
  )
end
