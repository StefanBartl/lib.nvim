-- TESTS/fs_etag_spec.lua -- lib.nvim.fs.etag: the version tag of some bytes.

return function(H)
  local ok = H.ok
  local etag = require("lib.nvim.fs.etag")

  ---Deep comparison (the shared `H.eq` compares references).
  local function eq(a, b, msg)
    if not vim.deep_equal(a, b) then
      error(("FAIL %s: expected %s, got %s"):format(msg or "", vim.inspect(b), vim.inspect(a)), 2)
    end
  end

  -- known vectors
  eq(
    etag.sha256("hello"),
    "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
    "sha256 of hello"
  )
  eq(
    etag.sha256(""),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "sha256 of nothing"
  )
  eq(etag.of("hello"), "sha256:2cf24dba5fb0a30e", "the tag: prefix and 16 digits")
  eq(#etag.of("x"), #"sha256:" + 16)
  ok(etag.of("x"):match("^sha256:%x+$"), "lowercase hex")
  eq(etag.of("same"), etag.of("same"), "the same every time")
  ok(etag.of("a") ~= etag.of("b"), "different bytes, different tag")
  ok(etag.of("a\n") ~= etag.of("a\r\n"), "a line ending changes the tag")

  -- a NUL byte is no error (vim.fn.sha256 itself refuses a string with one, hence this module)
  local with_nul = etag.sha256("a\0b")
  eq(#with_nul, 64)
  ok(with_nul ~= etag.sha256("ab"), "a NUL is not ignored")
  eq(with_nul, etag.sha256("a\255\254b"), "a NUL is hashed as two other bytes")
  ok(etag.of("a\0b") ~= etag.of("a\0c"), "texts with a NUL still tell apart")
  eq(etag.of(("\0"):rep(1000)), etag.of(("\0"):rep(1000)), "only NULs")
  ok(etag.of(("x"):rep(5 * 1024 * 1024)):match("^sha256:"), "a 5 MB text")
end
