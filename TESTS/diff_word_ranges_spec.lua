-- TESTS/diff_word_ranges_spec.lua — lib.nvim.diff.word_ranges
--
-- The spans of a changed line come back as 0-based [from, to) byte ranges, on code-point
-- boundaries; a byte that is no part of a well-formed sequence is a unit of its own.

return function(H)
  local ok = H.ok
  local word_ranges = require("lib.nvim.diff.word_ranges")

  --- `eq` that compares tables by content.
  local function eq(a, b, msg)
    if type(a) == "table" or type(b) == "table" then
      a, b = vim.inspect(a), vim.inspect(b)
    end
    H.eq(a, b, msg)
  end

  -- equal strings: nothing changed
  eq(word_ranges("same", "same"), { a = {}, b = {} }, "equal strings have no ranges")
  eq(word_ranges("", ""), { a = {}, b = {} }, "two empty strings")

  -- a replacement
  eq(
    word_ranges("local x = 1", "local y = 1"),
    { a = { { 6, 7 } }, b = { { 6, 7 } } },
    "one character replaced"
  )
  -- pure insertion / deletion: only one side has a range
  eq(word_ranges("ab", "aXb"), { a = {}, b = { { 1, 2 } } }, "insertion")
  eq(word_ranges("aXb", "ab"), { a = { { 1, 2 } }, b = {} }, "deletion")
  eq(word_ranges("", "abc"), { a = {}, b = { { 0, 3 } } }, "everything added")
  eq(word_ranges("abc", ""), { a = { { 0, 3 } }, b = {} }, "everything removed")

  -- two separate changes
  local two = word_ranges("a1b2c", "aXbYc")
  eq(two, { a = { { 1, 2 }, { 3, 4 } }, b = { { 1, 2 }, { 3, 4 } } }, "two hunks, in order")

  -- multi-byte code points move as one unit: never a range inside a character
  eq(
    word_ranges("a\xC3\xA4b", "a\xC3\xB6b"),
    { a = { { 1, 3 } }, b = { { 1, 3 } } },
    "ä -> ö is one two-byte range, not one byte"
  )
  eq(
    word_ranges("x\xE2\x82\xACy", "xy"),
    { a = { { 1, 4 } }, b = {} },
    "a three-byte character removed whole"
  )
  eq(
    word_ranges("a\xF0\x9F\x98\x80", "a\xF0\x9F\x98\x81"),
    { a = { { 1, 5 } }, b = { { 1, 5 } } },
    "a four-byte character replaced whole"
  )

  -- invalid UTF-8: every bad byte is its own unit, and nothing throws
  local bad = word_ranges("a\xFFb", "a\xFEb")
  eq(bad, { a = { { 1, 2 } }, b = { { 1, 2 } } }, "malformed bytes compared one by one")

  -- the algorithm is passed through
  for _, alg in ipairs({ "myers", "minimal", "patience", "histogram" }) do
    local r = word_ranges("local x = 1", "local y = 1", alg)
    ok(r ~= nil, alg .. " works")
    eq(r.a, { { 6, 7 } }, alg .. ": same change found")
  end

  -- not strings: nil, no error
  eq(word_ranges(nil, "a"), nil, "nil argument")
  eq(word_ranges("a", 5), nil, "number argument")

  -- the ranges describe real substrings
  do
    local a, b = "the quick brown fox", "the quack brown fix"
    local r = word_ranges(a, b)
    local old, new = {}, {}
    for _, rg in ipairs(r.a) do
      old[#old + 1] = a:sub(rg[1] + 1, rg[2])
    end
    for _, rg in ipairs(r.b) do
      new[#new + 1] = b:sub(rg[1] + 1, rg[2])
    end
    eq(old, { "i", "o" }, "changed text of the old side")
    eq(new, { "a", "i" }, "changed text of the new side")
  end

  -- review of 53cfc42: a change at the END of the line must not mark the last common unit
  eq(word_ranges("abc", "ab"), { a = { { 2, 3 } }, b = {} }, "trailing character removed")
  eq(word_ranges("ab", "abc"), { a = {}, b = { { 2, 3 } } }, "trailing character added")
  eq(word_ranges("foo", "foo bar"), { a = {}, b = { { 3, 7 } } }, "a word appended")
  eq(word_ranges("x = 1", "x = 1;"), { a = {}, b = { { 5, 6 } } }, "a semicolon appended")
  eq(word_ranges("x = 1;", "x = 1"), { a = { { 5, 6 } }, b = {} }, "a semicolon removed")
  for _, alg in ipairs({ "myers", "minimal", "patience", "histogram" }) do
    eq(
      word_ranges("abc", "ab", alg),
      { a = { { 2, 3 } }, b = {} },
      alg .. ": same at the end of the line"
    )
  end

  -- a line break or a NUL inside the text is an ordinary unit, never a throw or a drifting range
  eq(
    word_ranges("a\nb\nc", "a\nX\nc"),
    { a = { { 2, 3 } }, b = { { 2, 3 } } },
    "a line feed inside"
  )
  eq(
    word_ranges("a\nb", "a\nc"),
    { a = { { 2, 3 } }, b = { { 2, 3 } } },
    "a change after a line feed"
  )
  eq(word_ranges("a\r\nb", "a\r\nc"), { a = { { 3, 4 } }, b = { { 3, 4 } } }, "CRLF inside")
  eq(
    word_ranges("a\255\nb", "a\254\nc"),
    { a = { { 1, 2 }, { 3, 4 } }, b = { { 1, 2 }, { 3, 4 } } },
    "invalid byte and line feed"
  )
  eq(word_ranges("x\0y", "x\0z"), { a = { { 2, 3 } }, b = { { 2, 3 } } }, "a NUL byte is one unit")
  eq(word_ranges("", "ab"), { a = {}, b = { { 0, 2 } } }, "from nothing")
  eq(word_ranges("ab", ""), { a = { { 0, 2 } }, b = {} }, "to nothing")

  -- a stray or truncated byte is its own unit, a well-formed neighbour keeps its two bytes
  eq(
    word_ranges("a\195", "a\195\164"),
    { a = { { 1, 2 } }, b = { { 1, 3 } } },
    "truncated sequence vs the full character"
  )
end
