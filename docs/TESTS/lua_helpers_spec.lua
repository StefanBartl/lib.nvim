-- docs/TESTS/lua_helpers_spec.lua — lib.lua.{uuid,numeral,diff,error,yaml,time,strings,tables}
--
-- Covers the editor-independent `lib.lua.*` namespace. Nothing in here may
-- touch the `vim` API (the namespace's defining constraint), so these specs
-- are pure input/output assertions.

return function(H)
  local eq, ok = H.eq, H.ok

  -- --------------------------------------------------------------- lib.lua.uuid
  local uuid = require("lib.lua.uuid")

  local u = uuid.generate()
  ok(u:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil,
    "uuid.generate: matches the UUIDv4 shape (version nibble 4, variant 8/9/a/b)")
  ok(uuid.generate() ~= uuid.generate(), "uuid.generate: consecutive calls differ")
  eq(#uuid.format(u, "compact"), 32, "uuid.format: compact strips hyphens")
  eq(uuid.format(u, "upper"), u:upper(), "uuid.format: upper")
  eq(uuid.format(u, "braced"), "{" .. u .. "}", "uuid.format: braced")
  eq(uuid.format(u, "nonsense"), u, "uuid.format: unknown style passes through")

  -- ------------------------------------------------------------ lib.lua.numeral
  local roman = require("lib.lua.numeral").roman
  local alpha = require("lib.lua.numeral").alpha

  eq(roman.to_roman(1), "I", "roman.to_roman: 1")
  eq(roman.to_roman(4), "IV", "roman.to_roman: subtractive 4")
  eq(roman.to_roman(1990), "MCMXC", "roman.to_roman: 1990")
  eq(roman.to_roman(3999), "MMMCMXCIX", "roman.to_roman: upper bound")
  eq(roman.to_roman(0), nil, "roman.to_roman: rejects 0")
  eq(roman.to_roman(4000), nil, "roman.to_roman: rejects out-of-range")
  eq(roman.to_int("MCMXC"), 1990, "roman.to_int: 1990")
  eq(roman.to_int("iv"), 4, "roman.to_int: case-insensitive")
  eq(roman.to_int("IIII"), nil, "roman.to_int: rejects non-canonical IIII")

  eq(alpha.to_alpha(1), "a", "alpha.to_alpha: 1 -> a")
  eq(alpha.to_alpha(26), "z", "alpha.to_alpha: 26 -> z")
  eq(alpha.to_alpha(27), "aa", "alpha.to_alpha: bijective rollover 27 -> aa")
  eq(alpha.to_int("aa"), 27, "alpha.to_int: aa -> 27")
  eq(alpha.to_int("AB"), 28, "alpha.to_int: case-insensitive")
  eq(alpha.to_int("a1"), nil, "alpha.to_int: rejects non-letters")

  -- --------------------------------------------------------------- lib.lua.diff
  local dlines = require("lib.lua.diff").lines
  local myers = require("lib.lua.diff").myers

  eq(dlines.diff({ "a", "b" }, { "a", "b" }), nil, "diff.lines: identical arrays -> nil")
  ok(dlines.diff({ "a", "b", "c" }, { "a", "x", "c" }) ~= nil, "diff.lines: substitution -> splice region")

  local ops = myers.diff({ "a", "b", "c" }, { "a", "x", "c" })
  eq(ops[1].op, "equal", "diff.myers: common prefix is equal")
  eq(ops[1].value, "a", "diff.myers: prefix value")
  eq(ops[#ops].op, "equal", "diff.myers: common suffix is equal")
  eq(ops[#ops].value, "c", "diff.myers: suffix value")
  for _, o in ipairs(myers.diff({ "x", "y" }, { "x", "y" })) do
    eq(o.op, "equal", "diff.myers: identical inputs yield only equal ops")
  end

  -- -------------------------------------------------------------- lib.lua.error
  local E = require("lib.lua.error")

  local e = E.new("kind_x", "msg_y", { a = 1 })
  ok(E.is(e), "error.is: recognizes error.new output")
  ok(not E.is({}), "error.is: rejects a plain table")
  eq(e.kind, "kind_x", "error.new: kind")
  eq(e.data.a, 1, "error.new: data passthrough")

  -- safe_call must forward multiple return values (LuaJIT has no table.pack,
  -- so this exercises the 5.1 fallback).
  local sok, a, b = E.safe_call(function(x, y) return x + y, x * y end, 3, 4)
  ok(sok, "error.safe_call: reports success")
  eq(a, 7, "error.safe_call: first return value")
  eq(b, 12, "error.safe_call: second return value")

  local fok, ferr = E.safe_call(function() error("boom") end)
  ok(not fok, "error.safe_call: reports failure")
  ok(E.is(ferr), "error.safe_call: failure yields a structured error")
  eq(ferr.kind, "runtime_error", "error.safe_call: failure kind")
  ok(tostring(ferr.message):match("boom") ~= nil, "error.safe_call: traceback mentions the error")

  -- --------------------------------------------------------------- lib.lua.yaml
  local yaml = require("lib.lua.yaml")

  local data = yaml.simple_parse("name: test\ncount: 3\nflag: true\nquoted: 'hi'\n")
  ok(data ~= nil, "yaml.simple_parse: returns data")
  eq(data.name, "test", "yaml: bare string")
  eq(data.count, 3, "yaml: numeric coercion")
  eq(data.flag, true, "yaml: boolean coercion")
  eq(data.quoted, "hi", "yaml: quotes stripped")

  local nested = yaml.simple_parse("root:\n  child: 1\n")
  ok(nested ~= nil and nested.root ~= nil, "yaml: indentation nesting")
  eq(nested.root.child, 1, "yaml: nested value")

  -- --------------------------------------------------------------- lib.lua.time
  local presets = require("lib.lua.time.presets")
  local tfmt = require("lib.lua.time.format")

  local now = os.time({ year = 2026, month = 7, day = 16, hour = 12, min = 0, sec = 0 })
  local today = presets.today(now)
  ok(today.from <= now and today.to >= now, "time.presets: today spans the reference time")
  ok(presets.yesterday(now).to <= now, "time.presets: yesterday ends at or before now")
  ok(presets.this_year(now).from < now, "time.presets: this_year starts before now")

  local ts = os.time({ year = 2026, month = 7, day = 14, hour = 14, min = 32, sec = 5 })
  eq(tfmt.format_timestamp(ts, "iso"), "2026-07-14T14:32:05", "time.format: iso")
  eq(tfmt.format_timestamp(ts, "short"), "2026-07-14", "time.format: short")
  eq(tfmt.format_timestamp(ts, "filename"), "20260714_143205", "time.format: filename is path-safe")
  eq(tfmt.format_timestamp(ts, "unix"), tostring(ts), "time.format: unix")
  eq(tfmt.format_timestamp(ts, "bogus"), tfmt.format_timestamp(ts, "iso"), "time.format: unknown style falls back to iso")

  -- ------------------------------------------------------------ lib.lua.strings
  local utf8m = require("lib.lua.strings.utf8")
  eq(utf8m.encode(65), "A", "strings.utf8: encode ascii")
  eq(utf8m.encode(0x20AC), "\226\130\172", "strings.utf8: encode euro sign")
  eq(utf8m.char_len(string.byte("A")), 1, "strings.utf8: ascii lead byte length")
  eq(utf8m.char_len(226), 3, "strings.utf8: 3-byte lead byte length")
  eq(utf8m.decode("\226\130\172", 1), 0x20AC, "strings.utf8: decode round-trips encode")
  local cps = 0
  for _ in utf8m.iter("aé€") do
    cps = cps + 1
  end
  eq(cps, 3, "strings.utf8: iter counts codepoints, not bytes")

  local enc = require("lib.lua.strings.encoding")
  eq(enc.url_encode("a b&c"), "a%20b%26c", "strings.encoding: url_encode")
  eq(enc.url_decode("a%20b%26c"), "a b&c", "strings.encoding: url_decode")
  eq(enc.base64_encode("hello"), "aGVsbG8=", "strings.encoding: base64_encode pads")
  eq(enc.base64_decode("aGVsbG8="), "hello", "strings.encoding: base64_decode")
  eq(enc.base64_decode(enc.base64_encode("any carnal pleasure")), "any carnal pleasure",
    "strings.encoding: base64 round-trip")

  local dist = require("lib.lua.strings.distance")
  eq(dist.levenshtein("kitten", "sitting"), 3, "strings.distance: classic kitten/sitting = 3")
  eq(dist.levenshtein("", "abc"), 3, "strings.distance: empty vs abc")
  eq(dist.similarity("abc", "abc"), 1, "strings.distance: identical -> 1")

  local sfmt = require("lib.lua.strings.format")
  eq(sfmt.format_bytes(512), "512 B", "strings.format: bytes below 1K")
  eq(sfmt.format_bytes(1536), "1.5 KB", "strings.format: KB with decimal")
  eq(sfmt.format_number(1234567), "1,234,567", "strings.format: 7 digits")
  eq(sfmt.format_number(123456), "123,456", "strings.format: 6 digits (no leading separator)")
  eq(sfmt.format_number(123), "123", "strings.format: 3 digits untouched")
  eq(sfmt.format_number(-1234567), "-1,234,567", "strings.format: negative")

  local loc = require("lib.lua.strings.location")
  local l1 = loc.parse_location("src/foo.lua:12:5")
  eq(l1.path, "src/foo.lua", "strings.location: path:line:col path")
  eq(l1.line, 12, "strings.location: path:line:col line")
  eq(l1.col, 5, "strings.location: path:line:col col")
  eq(loc.parse_location("src/foo.lua:12").line, 12, "strings.location: path:line")
  eq(loc.parse_location("src/foo.lua(12:5)").col, 5, "strings.location: path(line:col)")
  eq(loc.parse_location("src/foo.lua +12").line, 12, "strings.location: path +line")
  eq(loc.parse_location("nonsense"), nil, "strings.location: unparseable -> nil")

  local case = require("lib.lua.strings.case")
  eq(case.case_shape("abc"), "lower", "strings.case: lower shape")
  eq(case.case_shape("ABC"), "upper", "strings.case: upper shape")
  eq(case.case_shape("Abc"), "capital", "strings.case: capital shape")
  eq(case.case_shape("aBc"), "mixed", "strings.case: mixed shape")
  eq(case.apply_shape("xyz", "capital"), "Xyz", "strings.case: apply capital")
  eq(case.apply_shape("xYz", "mixed"), "xYz", "strings.case: mixed is a no-op")
  eq(case.change_case("hello world", "title"), "Hello World", "strings.case: title")
  eq(case.change_case("hello world", "sentence"), "Hello world", "strings.case: sentence")

  local wrap = require("lib.lua.strings.wrap")
  eq(wrap.center_text("ab", 6), "  ab  ", "strings.wrap: center_text")
  eq(wrap.center_text("toolong", 3), "toolong", "strings.wrap: overlong text passes through")
  eq(#wrap.center_text_lines({ "a", "bb" }, 5), 2, "strings.wrap: center_text_lines maps every line")

  -- The aggregator must re-export the new submodules alongside the old ones.
  local strings = require("lib.lua.strings")
  for _, fn in ipairs({
    "utf8_encode", "utf8_decode", "utf8_char_len", "utf8_iter",
    "url_encode", "url_decode", "base64_encode", "base64_decode",
    "levenshtein", "similarity", "format_bytes", "format_number",
    "parse_location", "case_shape", "apply_shape", "change_case",
    "center_text", "center_text_lines",
  }) do
    eq(type(strings[fn]), "function", "lib.lua.strings aggregator exports " .. fn)
  end
  eq(type(strings.trim), "function", "lib.lua.strings: pre-existing trim still exported")

  -- ------------------------------------------------------------- lib.lua.tables
  local tables = require("lib.lua.tables")

  local dst = { a = 1, nested = { x = 1, y = 2 } }
  tables.deep_merge(dst, { b = 2, nested = { y = 99, z = 3 } })
  eq(dst.a, 1, "tables.deep_merge: untouched key survives")
  eq(dst.b, 2, "tables.deep_merge: new top-level key added")
  eq(dst.nested.x, 1, "tables.deep_merge: nested key not in src survives")
  eq(dst.nested.y, 99, "tables.deep_merge: nested key in src overwrites")
  eq(dst.nested.z, 3, "tables.deep_merge: nested key added")

  -- Scalars must replace tables rather than merge into them.
  local scalar_dst = { k = { deep = 1 } }
  tables.deep_merge(scalar_dst, { k = "now a string" })
  eq(scalar_dst.k, "now a string", "tables.deep_merge: scalar in src replaces a table in dst")
end
