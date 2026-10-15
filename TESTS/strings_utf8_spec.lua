-- TESTS/strings_utf8_spec.lua — lib.lua.strings.utf8.scrub / valid_len (and safe.utf8 on top of them).
--
-- Bytes are built with string.char so the file holds no invalid UTF-8 itself.

return function(H)
  local eq = H.eq
  local utf8 = require("lib.lua.strings.utf8")
  local safe = require("lib.lua.strings.safe")

  local function b(...)
    return string.char(...)
  end

  local function scrubbed(s)
    local clean, n = utf8.scrub(s)
    return clean, n
  end

  -- valid input is the same string with a zero count
  for _, case in ipairs({
    { "", "empty" },
    { "plain ascii", "ascii" },
    { "h" .. b(0xC3, 0xA9) .. "llo", "2-byte" },
    { b(0xE2, 0x82, 0xAC), "3-byte" },
    { b(0xF0, 0x9F, 0x98, 0x80), "4-byte" },
    { b(0xEF, 0xBF, 0xBD), "U+FFFD" },
    { b(0xF4, 0x8F, 0xBF, 0xBF), "U+10FFFF" },
    { b(0xED, 0x9F, 0xBF), "U+D7FF, the last before the surrogates" },
  }) do
    local clean, n = scrubbed(case[1])
    eq(clean, case[1], "scrub: valid " .. case[2] .. " is unchanged")
    eq(n, 0, "scrub: valid " .. case[2] .. " counts 0")
  end

  -- each invalid byte becomes one "?", with the right count
  for _, case in ipairs({
    { b(0x80), "?", 1, "a lone continuation byte" },
    { b(0xBF), "?", 1, "the last continuation byte" },
    { b(0xC0), "?", 1, "0xC0" },
    { b(0xC1), "?", 1, "0xC1" },
    { b(0xF5), "?", 1, "0xF5" },
    { b(0xFF), "?", 1, "0xFF" },
    { "a" .. b(0xC3), "a?", 1, "a 2-byte lead cut off at the end" },
    { b(0xE2, 0x82), "??", 2, "a 3-byte sequence cut off at the end" },
    { b(0xF0, 0x9F, 0x98), "???", 3, "a 4-byte sequence cut off at the end" },
    { b(0xE0, 0x80, 0x80), "???", 3, "an overlong form" },
    { b(0xC0, 0x80), "??", 2, "an overlong NUL" },
    { b(0xED, 0xA0, 0x80), "???", 3, "a UTF-16 surrogate" },
    { b(0xF4, 0x90, 0x80, 0x80), "????", 4, "a value above U+10FFFF" },
    { b(0xC3) .. "x", "?x", 1, "a lead followed by a non-continuation byte" },
    { "ok" .. b(0xFF) .. "ok" .. b(0xFE), "ok?ok?", 2, "bad bytes between valid text" },
  }) do
    local clean, n = scrubbed(case[1])
    eq(clean, case[2], "scrub: " .. case[4])
    eq(n, case[3], "scrub: " .. case[4] .. " (count)")
  end

  -- a valid character next to bad bytes survives
  local mixed, mixed_n = scrubbed(b(0xFF) .. b(0xC3, 0xA9) .. b(0x80))
  eq(mixed, "?" .. b(0xC3, 0xA9) .. "?", "scrub: a valid character between bad bytes stays")
  eq(mixed_n, 2, "scrub: ... count")

  -- custom replacement
  local custom, custom_n = utf8.scrub("a" .. b(0xFF) .. b(0xFE) .. "b", "")
  eq(custom, "ab", "scrub: an empty replacement drops the bytes")
  eq(custom_n, 2, "scrub: ... and still counts them")
  local fffd = b(0xEF, 0xBF, 0xBD)
  eq(select(1, utf8.scrub("x" .. b(0xFF), fffd)), "x" .. fffd, "scrub: a multi-byte replacement")

  -- valid_len
  eq(utf8.valid_len("abc", 1), 1, "valid_len: ASCII")
  eq(utf8.valid_len(b(0xC3, 0xA9), 1), 2, "valid_len: 2-byte")
  eq(utf8.valid_len("x" .. b(0xE2, 0x82, 0xAC), 2), 3, "valid_len: 3-byte at an offset")
  eq(utf8.valid_len(b(0xF0, 0x9F, 0x98, 0x80), 1), 4, "valid_len: 4-byte")
  eq(utf8.valid_len(b(0xE2, 0x82), 1), nil, "valid_len: truncated")
  eq(utf8.valid_len(b(0x80), 1), nil, "valid_len: continuation byte")
  eq(utf8.valid_len("abc", 4), nil, "valid_len: past the end")

  -- the pre-existing safe.utf8 is the same rule without the count
  eq(
    safe.utf8("a" .. b(0xFF) .. b(0xED, 0xA0, 0x80) .. "z"),
    "a????z",
    "safe.utf8: delegates to scrub"
  )
  eq(safe.utf8("plain"), "plain", "safe.utf8: ASCII unchanged")

  -- linear: a long run of bad bytes does not go quadratic
  local big = string.rep(b(0xFF), 200000)
  local t0 = vim.uv.hrtime()
  local clean, n = utf8.scrub(big)
  local ms = (vim.uv.hrtime() - t0) / 1e6
  eq(#clean, 200000, "scrub: 200k bad bytes -> 200k replacements")
  eq(n, 200000, "scrub: ... counted")
  H.ok(ms < 3000, ("scrub: 200k bad bytes stay linear (%.0f ms)"):format(ms))
end
