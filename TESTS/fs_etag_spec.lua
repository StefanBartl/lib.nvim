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

  -- the NUL guard is a plain byte search: a wrong start index or a lost plain flag would miss a NUL at an edge
  eq(etag.sha256("\0x"), etag.sha256("\255\254x"), "a NUL as the first byte")
  eq(etag.sha256("x\0"), etag.sha256("x\255\254"), "a NUL as the last byte")
  eq(etag.sha256("\0"), etag.sha256("\255\254"), "a NUL as the only byte")
  eq(
    etag.sha256("a\0b\0c"),
    etag.sha256("a\255\254b\255\254c"),
    "every NUL is replaced, not only the first"
  )
  local mb = ("x"):rep(1024 * 1024)
  eq(etag.sha256(mb .. "\0"), etag.sha256(mb .. "\255\254"), "a NUL at the very end of a 1 MB text")
  eq(
    etag.sha256("\0" .. mb),
    etag.sha256("\255\254" .. mb),
    "a NUL at the very start of a 1 MB text"
  )
  ok(etag.sha256(mb .. "\0") ~= etag.sha256(mb), "the NUL after 1 MB is not ignored")

  -- a text without a NUL (nearly every text) costs about one hash. Searching it with the `%z` pattern class ran the
  -- pattern matcher once per byte and made `etag.sha256` over twice as slow as `vim.fn.sha256` (measured 2.3x); a
  -- plain search stays near 1.0x. Best of several rounds on both sides, so one slow round (GC, a busy machine) does
  -- not decide, and a limit far from both numbers.
  local function best_ms(fn)
    local best = math.huge
    for _ = 1, 7 do
      local t0 = vim.uv.hrtime()
      fn()
      best = math.min(best, (vim.uv.hrtime() - t0) / 1e6)
    end
    return best
  end
  local big = ("0123456789abcdef"):rep(64 * 1024)
  local bare = best_ms(function()
    return vim.fn.sha256(big)
  end)
  local guarded = best_ms(function()
    return etag.sha256(big)
  end)
  ok(
    guarded < bare * 1.6,
    ("the NUL guard is cheap next to the hash (hash %.2f ms, with guard %.2f ms)"):format(
      bare,
      guarded
    )
  )

  -- not for a fast-event context (documented): vim.fn.sha256 raises E5560 there, so both functions do
  local fast = {}
  local timer = assert(vim.uv.new_timer())
  timer:start(0, 0, function()
    fast.in_fast_event = vim.in_fast_event()
    fast.sha256 = { pcall(etag.sha256, "x") }
    fast.of = { pcall(etag.of, "x") }
    fast.done = true
  end)
  ok(
    vim.wait(5000, function()
      return fast.done
    end, 10),
    "the timer callback ran"
  )
  timer:stop()
  timer:close()
  eq(fast.in_fast_event, true, "the callback is a fast-event context")
  eq(fast.sha256[1], false, "sha256 raises in a fast event")
  eq(fast.of[1], false, "of raises in a fast event")
  ok(tostring(fast.of[2]):find("fast event", 1, true), "E5560: " .. tostring(fast.of[2]))
end
