-- TESTS/strings_safe_spec.lua — lib.lua.strings.safe
--
-- Text from somebody else's repository must not be able to move the cursor, recolour the
-- terminal, reorder or hide characters, or smuggle in bytes that are not UTF-8.

return function(H)
  local eq, ok = H.eq, H.ok
  local safe = require("lib.lua.strings.safe")
  eq(require("lib.lua.strings").safe, safe, "reachable through the aggregator")

  -- clean
  eq(safe.clean("plain subject"), "plain subject", "clean: ordinary text is untouched")
  eq(safe.clean("a\tb"), "a b", "clean: a tab becomes a space")
  eq(safe.clean("a\27[31mb"), "a?[31mb", "clean: ESC is replaced")
  eq(safe.clean("a\rb\0c\127d"), "a?b?c?d", "clean: CR, NUL and DEL are replaced")
  eq(safe.clean("a\194\155b"), "a?b", "clean: the C1 control U+009B is replaced")
  eq(safe.clean("é€漢"), "é€漢", "clean: multi-byte characters survive")
  eq(safe.clean("a\226\128\174b"), "a?b", "clean: U+202E (bidi override) is replaced")
  eq(safe.clean("a\226\128\139b"), "a?b", "clean: U+200B (zero-width space) is replaced")
  eq(safe.clean("a\226\128\168b"), "a?b", "clean: U+2028 is replaced")
  eq(safe.clean("a\226\129\166b"), "a?b", "clean: U+2066 is replaced")
  eq(safe.clean("\239\187\191x"), "?x", "clean: the byte-order mark is replaced")

  -- the cap counts characters, never cuts one in half
  local long = ("é"):rep(500)
  local cut = safe.clean(long)
  eq(cut, ("é"):rep(safe.MAX_LINE) .. "…", "clean: default cap, marked with an ellipsis")
  eq(safe.clean("abcdef", 3), "abc…", "clean: an explicit cap")
  eq(safe.clean("abc", 3), "abc", "clean: exactly at the cap is not cut")
  eq(safe.clean("漢漢漢", 2), "漢漢…", "clean: a 3-byte character is kept whole")

  -- utf8
  eq(safe.utf8("ascii"), "ascii", "utf8: ASCII as is")
  eq(safe.utf8("é漢😀"), "é漢😀", "utf8: valid text as is")
  eq(safe.utf8("a\255b"), "a?b", "utf8: an invalid byte")
  eq(safe.utf8("a\128b"), "a?b", "utf8: a stray continuation byte")
  eq(safe.utf8("a\195"), "a?", "utf8: a truncated sequence at the end")
  eq(safe.utf8("a\192\128b"), "a??b", "utf8: an overlong form")
  eq(safe.utf8("\237\160\128"), "???", "utf8: a surrogate")
  eq(safe.utf8("\244\144\128\128"), "????", "utf8: above U+10FFFF")

  -- one_line / lines
  eq(safe.one_line("first\nsecond"), "first", "one_line: first line only")
  eq(safe.one_line("first\r\nsecond"), "first", "one_line: CRLF too")
  eq(safe.one_line(nil), "", "one_line: nil is empty")
  eq(safe.one_line(42), "42", "one_line: a number is stringified")
  local lines, total, exact = safe.lines("a\27b\nc")
  eq(#lines, 2, "lines: two lines")
  eq(lines[1], "a?b", "lines: each line is cleaned")
  ok(lines[2] == "c", "lines: second line")
  eq(total, 2, "lines: total")
  eq(exact, true, "lines: the count is exact")
  lines, total = safe.lines("1\n2\n3\n4\n5", 2)
  eq(#lines, 2, "lines: max limits what is returned")
  eq(total, 5, "lines: ... but not what is counted")
  lines = safe.lines("x", nil, 4)
  eq(lines[1], "x", "lines: max_chars is passed through")
  eq(safe.lines(("y"):rep(50), nil, 5)[1], "yyyyy…", "lines: per-line cap")

  -- further invisible / re-ordering characters
  for label, ch in pairs({
    ["word joiner U+2060"] = "\226\129\160",
    ["Arabic letter mark U+061C"] = "\216\156",
    ["tag character U+E0041"] = "\243\160\129\129",
    ["Hangul filler U+3164"] = "\227\133\164",
    ["soft hyphen U+00AD"] = "\194\173",
    ["braille blank U+2800"] = "\226\160\128",
    ["annotation anchor U+FFF9"] = "\239\191\185",
  }) do
    eq(safe.clean("a" .. ch .. "b"), "a?b", "clean: " .. label)
  end
  eq(safe.clean("a\239\184\143b"), "a\239\184\143b", "clean: a variation selector stays")

  -- bounded by what is shown
  eq(
    safe.clean(("x"):rep(5 * 1024 * 1024)),
    ("x"):rep(safe.MAX_LINE) .. "…",
    "clean: a 5 MB line is cut"
  )
end
