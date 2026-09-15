-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/lua_helpers_spec.lua — lib.lua.{uuid,numeral,diff,error,yaml,time,strings,tables}
--
-- Covers the editor-independent `lib.lua.*` namespace. Nothing in here may
-- touch the `vim` API (the namespace's defining constraint), so these specs
-- are pure input/output assertions.

return function(H)
  local eq, ok = H.eq, H.ok

  -- --------------------------------------------------------------- lib.lua.uuid
  local uuid = require("lib.lua.uuid")

  local u = uuid.generate()
  ok(
    u:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil,
    "uuid.generate: matches the UUIDv4 shape (version nibble 4, variant 8/9/a/b)"
  )
  ok(uuid.generate() ~= uuid.generate(), "uuid.generate: consecutive calls differ")
  eq(#uuid.format(u, "compact"), 32, "uuid.format: compact strips hyphens")
  eq(uuid.format(u, "upper"), u:upper(), "uuid.format: upper")
  eq(uuid.format(u, "braced"), "{" .. u .. "}", "uuid.format: braced")
  -- The unknown style is the case.
  ---@diagnostic disable-next-line: param-type-mismatch
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
  ok(
    dlines.diff({ "a", "b", "c" }, { "a", "x", "c" }) ~= nil,
    "diff.lines: substitution -> splice region"
  )

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
  local sok, a, b = E.safe_call(function(x, y)
    return x + y, x * y
  end, 3, 4)
  ok(sok, "error.safe_call: reports success")
  eq(a, 7, "error.safe_call: first return value")
  eq(b, 12, "error.safe_call: second return value")

  local fok, ferr = E.safe_call(function()
    error("boom")
  end)
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

  -- yaml.encode -- checked against simple_parse, not just eyeballed: every
  -- case below is round-tripped back through the decoder.
  local yaml_null = require("lib.lua.null")

  local simple_map = { name = "Ana", count = 3, active = true }
  local simple_encoded = yaml.encode(simple_map)
  ok(simple_encoded ~= nil, "yaml.encode: no error on a flat map")
  local simple_roundtrip = yaml.simple_parse(simple_encoded)
  eq(simple_roundtrip.name, "Ana", "yaml.encode round-trip: bare string value")
  eq(simple_roundtrip.count, 3, "yaml.encode round-trip: number value")
  eq(simple_roundtrip.active, true, "yaml.encode round-trip: boolean value")

  local nested_value = { user = { id = 1, tags = { "a", "b" } }, level = "error" }
  local nested_encoded = yaml.encode(nested_value)
  local nested_roundtrip = yaml.simple_parse(nested_encoded)
  eq(nested_roundtrip.level, "error", "yaml.encode round-trip: sibling of a nested map")
  eq(nested_roundtrip.user.id, 1, "yaml.encode round-trip: nested map value")
  eq(nested_roundtrip.user.tags[1], "a", "yaml.encode round-trip: nested list value")
  eq(nested_roundtrip.user.tags[2], "b", "yaml.encode round-trip: nested list value (2nd)")

  -- A list of multi-key maps needs the bare-"-"-plus-block form (simple_parse's
  -- own documented shorthand limit: "- a: 1" only reads ONE key per line).
  local list_of_maps = { records = { { a = 1, b = 2 }, { a = 3, b = 4 } } }
  local list_encoded = yaml.encode(list_of_maps)
  local list_roundtrip = yaml.simple_parse(list_encoded)
  eq(list_roundtrip.records[1].a, 1, "yaml.encode: multi-key list item, first record field a")
  eq(list_roundtrip.records[1].b, 2, "yaml.encode: multi-key list item, first record field b")
  eq(list_roundtrip.records[2].a, 3, "yaml.encode: multi-key list item, second record field a")

  -- Strings that would decode differently bare must be quoted.
  local quoting_cases = { yes = "true", num = "42", tilde = "~", colon = "a: b" }
  local quoting_encoded = yaml.encode(quoting_cases)
  local quoting_roundtrip = yaml.simple_parse(quoting_encoded)
  eq(
    quoting_roundtrip.yes,
    "true",
    'yaml.encode: the string "true" survives as a string, not a boolean'
  )
  eq(quoting_roundtrip.num, "42", 'yaml.encode: the string "42" survives as a string, not a number')
  eq(quoting_roundtrip.tilde, "~", 'yaml.encode: the string "~" survives as a string, not null')
  eq(
    quoting_roundtrip.colon,
    "a: b",
    "yaml.encode: a string containing ': ' is quoted so it isn't split"
  )

  -- The shared null sentinel round-trips to "key omitted" -- simple_parse's
  -- own documented null-as-absence design, not a new asymmetry.
  local null_encoded = yaml.encode({ a = 1, b = yaml_null.NULL })
  ok(
    null_encoded:find("b: null", 1, true) ~= nil,
    "yaml.encode: the shared NULL sentinel encodes as the literal null"
  )
  local null_roundtrip = yaml.simple_parse(null_encoded)
  eq(null_roundtrip.a, 1, "yaml.encode: sibling of a null value survives")
  eq(
    null_roundtrip.b,
    nil,
    "yaml.encode: null value round-trips to an omitted key, per simple_parse's design"
  )

  eq(yaml.encode({}), "", "yaml.encode: an empty table encodes to the empty document")

  local custom_indent = yaml.encode({ a = { b = 1 } }, { indent = 4 })
  ok(
    custom_indent:find("\n    b: 1", 1, true) ~= nil,
    "yaml.encode: custom indent width is honored"
  )

  local yaml_cyclic = {}
  yaml_cyclic.self = yaml_cyclic
  local cyclic_encoded, cyclic_err = yaml.encode(yaml_cyclic)
  eq(cyclic_encoded, nil, "yaml.encode: a cyclic table is refused, not looped forever")
  ok(cyclic_err ~= nil, "yaml.encode: cyclic refusal carries an error message")

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
  eq(
    -- The unknown style is the case.
    ---@diagnostic disable-next-line: param-type-mismatch
    tfmt.format_timestamp(ts, "bogus"),
    tfmt.format_timestamp(ts, "iso"),
    "time.format: unknown style falls back to iso"
  )

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
  eq(
    enc.base64_decode(enc.base64_encode("any carnal pleasure")),
    "any carnal pleasure",
    "strings.encoding: base64 round-trip"
  )
  eq(
    enc.html_escape([[<a href="x">Tom & Jerry</a>]]),
    "&lt;a href=&quot;x&quot;&gt;Tom &amp; Jerry&lt;/a&gt;",
    'strings.encoding: html_escape covers & < > "'
  )
  eq(enc.html_escape(nil), "", 'strings.encoding: html_escape(nil) -> ""')
  eq(enc.html_escape(""), "", 'strings.encoding: html_escape("") -> ""')

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
  eq(
    #wrap.center_text_lines({ "a", "bb" }, 5),
    2,
    "strings.wrap: center_text_lines maps every line"
  )

  -- The aggregator must re-export the new submodules alongside the old ones.
  local strings = require("lib.lua.strings")
  for _, fn in ipairs({
    "utf8_encode",
    "utf8_decode",
    "utf8_char_len",
    "utf8_iter",
    "url_encode",
    "url_decode",
    "base64_encode",
    "base64_decode",
    "levenshtein",
    "similarity",
    "format_bytes",
    "format_number",
    "parse_location",
    "case_shape",
    "apply_shape",
    "change_case",
    "center_text",
    "center_text_lines",
  }) do
    eq(type(strings[fn]), "function", "lib.lua.strings aggregator exports " .. fn)
  end
  eq(type(strings.trim), "function", "lib.lua.strings: pre-existing trim still exported")

  -- Regression: dedent's line-indent measurement used to call `find` without
  -- a capture group, so `spaces` was the match's end index (a number), and
  -- `#spaces` raised on every non-trivial call.
  eq(
    strings.dedent("  hello\n  world"),
    "hello\nworld",
    "strings.dedent: strips common leading indent"
  )
  eq(strings.dedent("hello"), "hello", "strings.dedent: no indent is a no-op")
  eq(
    strings.dedent("  a\n    b"),
    "a\n  b",
    "strings.dedent: strips only the common (smaller) indent, keeps relative nesting"
  )

  -- ------------------------------------------------------------- lib.lua.tables
  local tables = require("lib.lua.tables")

  -- Regression: a non-numeric key used to be compared against `n` (an
  -- integer) with `>`, raising "attempt to compare number with string"
  -- instead of correctly returning false — i.e. is_array crashed on exactly
  -- the input shape it exists to reject.
  eq(
    tables.is_array({ a = 1, b = 2 }),
    false,
    "tables.is_array: string keys -> false, not an error"
  )
  eq(tables.is_array({ 1, 2, 3 }), true, "tables.is_array: contiguous array -> true")
  eq(tables.is_array({}), true, "tables.is_array: empty table -> true")
  eq(tables.is_array({ 1, 2, [5] = 9 }), false, "tables.is_array: sparse array -> false")
  eq(tables.is_array({ 1, 2, x = 1 }), false, "tables.is_array: mixed array+string key -> false")

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

  -- tables.path_flatten — the data.nvim `:JSON lines`/`filter` building block.
  local flat, flat_err = tables.path_flatten({ user = { id = 1, name = "Ana" }, level = "error" })
  ok(flat ~= nil and flat_err == nil, "tables.path_flatten: no error on a plain nested object")
  ---@cast flat -nil
  eq(#flat, 3, "tables.path_flatten: one entry per leaf")
  eq(flat[1].path, "level", "tables.path_flatten: sorted key order (level before user.*)")
  eq(flat[1].value, "error", "tables.path_flatten: leaf value preserved")
  eq(flat[2].path, "user.id", "tables.path_flatten: nested path joined with default '.' sep")
  eq(flat[3].path, "user.name", "tables.path_flatten: sibling keys sorted")

  local arr_flat = tables.path_flatten({ tags = { "a", "b" } })
  ---@cast arr_flat -nil
  eq(arr_flat[1].path, "tags.1", "tables.path_flatten: array indices keep natural order")
  eq(arr_flat[2].path, "tags.2", "tables.path_flatten: array indices keep natural order (2nd)")

  local sep_flat = tables.path_flatten({ a = { b = 1 } }, { sep = "/" })
  ---@cast sep_flat -nil
  eq(sep_flat[1].path, "a/b", "tables.path_flatten: custom separator")

  local empty_flat = tables.path_flatten({ a = {} })
  ---@cast empty_flat -nil
  eq(empty_flat[1].path, "a", "tables.path_flatten: empty nested table is its own leaf")
  eq(
    type(empty_flat[1].value),
    "table",
    "tables.path_flatten: empty-table leaf keeps the table value"
  )

  local deep = { a = {} }
  local cursor = deep.a
  for _ = 1, 70 do
    cursor.next = {}
    cursor = cursor.next
  end
  local _, depth_err = tables.path_flatten(deep, { max_depth = 64 })
  ok(
    depth_err ~= nil,
    "tables.path_flatten: max_depth guard reports an error instead of recursing forever"
  )

  -- ---------------------------------------------------------------- lib.lua.xml
  local xml = require("lib.lua.xml")

  local simple_tree, simple_xml_err = xml.decode('<user id="1"><name>Ana</name></user>')
  ok(simple_xml_err == nil, "xml.decode: no error on a well-formed simple document")
  eq(simple_tree.tag, "user", "xml.decode: root tag")
  eq(simple_tree.attrs.id, "1", "xml.decode: attribute value")
  eq(simple_tree.children[1].tag, "name", "xml.decode: nested element tag")
  eq(simple_tree.children[1].children[1], "Ana", "xml.decode: leaf text content")

  local self_closing = xml.decode('<a><b/><c x="1"/></a>')
  eq(#self_closing.children, 2, "xml.decode: two self-closing children")
  eq(#self_closing.children[1].children, 0, "xml.decode: self-closing element has no children")
  eq(self_closing.children[2].attrs.x, "1", "xml.decode: attribute on a self-closing element")

  -- Insignificant whitespace-only text between elements is dropped; real
  -- text content is kept, entities resolved.
  local ws_tree = xml.decode("<a>\n  <b>1</b>\n  <c>&amp;&lt;&gt;</c>\n</a>")
  eq(#ws_tree.children, 2, "xml.decode: whitespace-only text nodes between children are dropped")
  eq(ws_tree.children[2].children[1], "&<>", "xml.decode: predefined entities are resolved")

  local numeric_entity = xml.decode("<a>&#65;&#x42;</a>")
  eq(numeric_entity.children[1], "AB", "xml.decode: numeric and hex character references")

  local cdata_tree = xml.decode("<a><![CDATA[<not a tag> & stuff]]></a>")
  eq(
    cdata_tree.children[1],
    "<not a tag> & stuff",
    "xml.decode: CDATA content is kept literal, unescaped"
  )

  local commented = xml.decode("<a><!-- a comment --><b>1</b></a>")
  eq(#commented.children, 1, "xml.decode: comments are discarded, not counted as content")

  local decl_tree = xml.decode('<?xml version="1.0" encoding="UTF-8"?>\n<a>1</a>')
  eq(decl_tree.tag, "a", "xml.decode: a leading <?xml ...?> declaration is skipped")

  local doctype_tree = xml.decode('<!DOCTYPE a [ <!ENTITY x "y"> ]>\n<a>1</a>')
  eq(doctype_tree.tag, "a", "xml.decode: a <!DOCTYPE ...> with an internal subset is skipped whole")

  local mismatched, mismatched_err = xml.decode("<a><b></c></a>")
  ok(mismatched == nil, "xml.decode: a mismatched closing tag is rejected")
  ok(mismatched_err ~= nil, "xml.decode: mismatched closing tag carries an error message")

  local unterminated, unterminated_err = xml.decode("<a><b>text")
  ok(
    unterminated == nil,
    "xml.decode: an unterminated element (EOF before its closing tag) is rejected"
  )
  ok(unterminated_err ~= nil, "xml.decode: unterminated element carries an error message")

  local multi_root, multi_root_err = xml.decode("<a/><b/>")
  ok(multi_root == nil, "xml.decode: more than one root element is rejected")
  ok(multi_root_err ~= nil, "xml.decode: multiple roots carries an error message")

  -- xml.encode -- compact by default (mirrors lib.lua.json.encode), pretty
  -- multi-line with an explicit indent, both checked by round-tripping
  -- through xml.decode.
  local encode_tree = {
    tag = "user",
    attrs = { id = "1" },
    children = { { tag = "name", attrs = {}, children = { "Ana" } } },
  }
  local compact_encoded, compact_err = xml.encode(encode_tree)
  ok(compact_err == nil, "xml.encode: no error on a simple tree")
  eq(
    compact_encoded,
    '<user id="1"><name>Ana</name></user>',
    "xml.encode: compact by default, one line"
  )

  local pretty_encoded = xml.encode.pretty(encode_tree)
  eq(
    pretty_encoded,
    '<user id="1">\n  <name>Ana</name>\n</user>',
    "xml.encode.pretty: multi-line, 2-space indent"
  )

  local roundtrip = xml.decode(compact_encoded)
  eq(roundtrip.tag, "user", "xml round-trip: tag survives")
  eq(roundtrip.attrs.id, "1", "xml round-trip: attribute survives")
  eq(roundtrip.children[1].children[1], "Ana", "xml round-trip: nested text survives")

  local escaped_encoded =
    xml.encode({ tag = "a", attrs = { q = '"<&>"' }, children = { "<x> & y" } })
  eq(
    escaped_encoded,
    '<a q="&quot;&lt;&amp;&gt;&quot;">&lt;x&gt; &amp; y</a>',
    "xml.encode: text and attribute values are escaped"
  )

  eq(xml.encode({ tag = "empty" }), "<empty/>", "xml.encode: no children -> self-closing")

  local self_closing_err_val, self_closing_err_msg = xml.encode({ notag = true })
  ok(self_closing_err_val == nil, "xml.encode: a table without a string 'tag' field is refused")
  ok(self_closing_err_msg ~= nil, "xml.encode: refusal carries an error message")

  local xml_cyclic = { tag = "a", children = {} }
  xml_cyclic.children[1] = xml_cyclic
  local xml_cyclic_encoded, xml_cyclic_err = xml.encode(xml_cyclic)
  eq(xml_cyclic_encoded, nil, "xml.encode: a cyclic element tree is refused, not looped forever")
  ok(xml_cyclic_err ~= nil, "xml.encode: cyclic refusal carries an error message")

  -- --------------------------------------------------------------- lib.lua.null
  local null = require("lib.lua.null")

  ok(null.is_null(null.NULL), "null.is_null: the sentinel itself is null")
  ok(not null.is_null(nil), "null.is_null: real Lua nil is not the sentinel")
  ok(not null.is_null(false), "null.is_null: false is not the sentinel")
  ok(not null.is_null({}), "null.is_null: an unrelated empty table is not the sentinel")
  eq(tostring(null.NULL), "null", "null.NULL: __tostring reads as 'null'")

  -- -------------------------------------------------------------- lib.lua.config
  local config = require("lib.lua.config")

  -- Unlike tables.deep_merge above, this one does not mutate its arguments
  -- and does not merge into list-like tables — it replaces them wholesale,
  -- which is the config-store behaviour cascade.nvim/spotlight.nvim need.
  local base = { a = 1, nested = { x = 1, y = 2 }, groups = { "a", "b", "c" } }
  local merged = config.deep_merge(base, { b = 2, nested = { y = 99 }, groups = { "x" } })
  eq(base.b, nil, "config.deep_merge: base is not mutated")
  eq(merged.a, 1, "config.deep_merge: untouched key survives")
  eq(merged.b, 2, "config.deep_merge: new top-level key added")
  eq(merged.nested.x, 1, "config.deep_merge: nested key not in override survives")
  eq(merged.nested.y, 99, "config.deep_merge: nested key in override overwrites")
  eq(#merged.groups, 1, "config.deep_merge: a list-like override replaces wholesale")
  eq(merged.groups[1], "x", "config.deep_merge: ...instead of merging index-by-index")

  eq(config.get({ a = { b = { c = 42 } } }, "a.b.c"), 42, "config.get: nested dot-path")
  eq(config.get({ a = 1 }, "a.b"), nil, "config.get: descending into a non-table -> nil")
  eq(config.get({ a = 1 }, "missing"), nil, "config.get: missing key -> nil")
  eq(config.get({ a = 1 }, nil), nil, "config.get: non-string path -> nil")

  -- --------------------------------------------------------------- lib.lua.dump
  local dump = require("lib.lua.dump")

  eq(dump.to_string(42), "(number) 42", "dump.to_string: scalar")
  eq(dump.to_string("hi"), "(string) hi", "dump.to_string: string")
  eq(dump.to_string(nil), "nil", "dump.to_string: nil")

  local plain = dump.to_lines({ a = 1 })
  eq(#plain, 2, "dump.to_lines: table header + one field")
  ok(plain[1]:match("%(table%)") ~= nil, "dump.to_lines: table header marker")
  ok(plain[2]:match("%[a%] = %(number%) 1") ~= nil, "dump.to_lines: field line")

  local cyclic = {}
  cyclic.self = cyclic
  local cyclic_lines = dump.to_lines(cyclic, { max_depth = 3 })
  ok(#cyclic_lines > 0, "dump.to_lines: cyclic table does not hang")
  ok(
    cyclic_lines[#cyclic_lines]:match("max depth reached") ~= nil,
    "dump.to_lines: cyclic table hits the depth cap"
  )

  local with_meta = setmetatable({ x = 1 }, { y = 2 })
  local meta_lines = dump.to_lines(with_meta)
  local joined = table.concat(meta_lines, "\n")
  ok(
    joined:match("%[x%] = %(number%) 1") ~= nil,
    "dump.to_lines: own field survives alongside a metatable"
  )
  ok(joined:match("metatable") ~= nil, "dump.to_lines: metatable is also dumped")

  -- -------------------------------------------------------------- lib.lua.class
  local class = require("lib.lua.class")

  local Animal = class.new("Animal")
  function Animal:init(name)
    self.name = name
  end
  function Animal:speak()
    return self.name .. " makes a sound"
  end

  local rex = Animal.new("Rex")
  eq(rex.name, "Rex", "class: init() ran during .new()")
  eq(rex:speak(), "Rex makes a sound", "class: own method callable")

  local Dog = Animal:extend("Dog")
  function Dog:speak() -- override
    return self.name .. " barks"
  end

  local fido = Dog.new("Fido")
  eq(fido.name, "Fido", "class: subclass instance inherits init() from the parent")
  eq(fido:speak(), "Fido barks", "class: subclass override wins over the parent's method")

  local Cat = Animal:extend("Cat") -- no override
  local felix = Cat.new("Felix")
  eq(
    felix:speak(),
    "Felix makes a sound",
    "class: no override -> falls through to the parent's method"
  )

  local Loud = {
    shout = function(self)
      return self.name:upper() .. "!!!"
    end,
    speak = function(self)
      return "should never win"
    end,
  }
  class.include(Dog, Loud)
  eq(fido:shout(), "FIDO!!!", "class.include: mixin method copied onto the target")
  eq(fido:speak(), "Fido barks", "class.include: target's own method wins over the mixin's")

  -- ------------------------------------------------------- lib.lua.strings.width
  local swidth = require("lib.lua.strings.width")

  eq(swidth.char_width(string.byte("a")), 1, "width.char_width: ascii is one column")
  eq(swidth.char_width(0x65E5), 2, "width.char_width: CJK ideograph is two columns")
  eq(swidth.char_width(0xFF21), 2, "width.char_width: fullwidth latin A is two columns")
  eq(swidth.char_width(0x0301), 0, "width.char_width: a combining accent takes no column")
  eq(swidth.char_width(0x200B), 0, "width.char_width: zero-width space takes no column")
  eq(swidth.char_width(0x1F600), 2, "width.char_width: emoji is two columns")

  eq(swidth.display_width(""), 0, "width.display_width: empty string")
  eq(swidth.display_width("abc"), 3, "width.display_width: ascii == byte length")
  -- "日本" is 6 bytes but 4 columns -- the whole reason this module exists.
  eq(#"日本", 6, "width: the CJK fixture really is 6 bytes")
  eq(swidth.display_width("日本"), 4, "width.display_width: CJK counts columns, not bytes")
  eq(swidth.display_width("aé"), 2, "width.display_width: multibyte latin is still one column")
  eq(
    swidth.display_width("e\u{0301}"),
    1,
    "width.display_width: a combining accent adds no column to its base"
  )

  -- Tabs advance to the next stop, so their width depends on the column
  -- they start at -- not a constant, which is why display_width is not just
  -- a sum over char_width.
  eq(swidth.display_width("\t"), 8, "width.display_width: a leading tab fills one stop")
  eq(swidth.display_width("a\tb"), 9, "width.display_width: tab advances to the next stop")
  eq(
    swidth.display_width("a\tb", { tabstop = 4 }),
    5,
    "width.display_width: opts.tabstop is honored"
  )
  eq(
    swidth.display_width("abcdefgh\t"),
    16,
    "width.display_width: a tab exactly on a stop still advances a full stop"
  )

  local trunc, trunc_w = swidth.truncate("日本語テキスト", 6)
  eq(trunc, "日本語", "width.truncate: cuts on a character boundary, not a byte one")
  eq(trunc_w, 6, "width.truncate: reports the resulting width")

  eq(
    (swidth.truncate("abcdef", 10)),
    "abcdef",
    "width.truncate: a string already inside the budget is returned unchanged"
  )

  -- An odd budget cannot fit a trailing double-width char, so the result
  -- comes out one column narrower rather than one column over.
  local odd, odd_w = swidth.truncate("日本語", 5)
  eq(odd, "日本", "width.truncate: a straddling wide char is dropped whole")
  eq(odd_w, 4, "width.truncate: ... leaving the result under the budget")

  local ell, ell_w = swidth.truncate("abcdefgh", 5, { ellipsis = "..." })
  eq(ell, "ab...", "width.truncate: the ellipsis fits inside the budget, not beyond it")
  eq(ell_w, 5, "width.truncate: ... and the reported width matches")
  eq(
    (swidth.truncate("abcdef", 2, { ellipsis = "....." })),
    "",
    "width.truncate: an ellipsis wider than the budget yields an empty result, not an over-wide one"
  )

  eq(swidth.pad_end("日本", 6), "日本  ", "width.pad_end: pads by columns, not bytes")
  eq(swidth.pad_start("日本", 6), "  日本", "width.pad_start: pads by columns")
  eq(swidth.pad_center("日本", 8), "  日本  ", "width.pad_center: pads by columns")
  eq(swidth.pad_end("日本", 2), "日本", "width.pad_end: no padding when already at/over width")
  eq(
    swidth.pad_center("ab", 5),
    " ab  ",
    "width.pad_center: an odd remainder goes right, matching core.pad_center"
  )

  -- The byte-based originals are deliberately left alone: this is the
  -- behavior difference the new module exists to offer an alternative to.
  local score = require("lib.lua.strings.core")
  eq(score.pad_end("日本", 6), "日本", "core.pad_end: still byte-based (6 bytes -> no padding)")

  -- Aggregator wiring: the three width-only names are flattened, the pad_*
  -- ones are not (they would shadow core's byte-based versions).
  local strings_agg = require("lib.lua.strings")
  eq(type(strings_agg.display_width), "function", "strings aggregator: display_width wired")
  eq(type(strings_agg.truncate), "function", "strings aggregator: truncate wired")
  eq(type(strings_agg.char_width), "function", "strings aggregator: char_width wired")
  eq(type(strings_agg.width.pad_end), "function", "strings aggregator: width submodule reachable")
  eq(
    strings_agg.pad_end("日本", 6),
    "日本",
    "strings aggregator: pad_end still resolves to core's byte-based version"
  )

  -- ------------------------------------------------------ lib.lua.context_manager
  local with = require("lib.lua.context_manager").with

  -- Success path: release runs, body's result is forwarded.
  do
    local released = 0
    local ok2, result = with(function()
      return { acquired = true }
    end, function()
      released = released + 1
    end, function(resource)
      return resource.acquired and "body-ran"
    end)
    eq(ok2, true, "with: reports ok on a normal body return")
    eq(result, "body-ran", "with: forwards body's return value")
    eq(released, 1, "with: release ran exactly once")
  end

  -- Multiple return values from body are forwarded, including in the
  -- presence of an embedded nil (the LuaJIT table.pack/unpack fallback).
  do
    local ok3, r1, r2, r3 = with(function()
      return {}
    end, function() end, function()
      return 1, nil, 3
    end)
    eq(ok3, true, "with: ok on multi-return body")
    eq(r1, 1, "with: first return value")
    eq(r2, nil, "with: embedded nil survives")
    eq(r3, 3, "with: third return value after the embedded nil")
  end

  -- body errors: release still runs, and the error surfaces to the caller.
  do
    local released = 0
    local ok4, err = with(function()
      return {}
    end, function()
      released = released + 1
    end, function()
      error("body boom")
    end)
    ok(not ok4, "with: reports not-ok when body errors")
    eq(released, 1, "with: release still ran despite the body error")
    ok(
      type(err) == "table" and tostring(err.message):match("body boom") ~= nil,
      "with: the error surfaces to the caller (structured, from error.safe_call)"
    )
  end

  -- A failed acquire short-circuits: release is never called, body never runs.
  do
    local released, body_ran = 0, false
    local ok5, err5 = with(function()
      return nil, "acquire failed"
    end, function()
      released = released + 1
    end, function()
      body_ran = true
    end)
    ok(not ok5, "with: reports not-ok when acquire fails")
    eq(err5, "acquire failed", "with: acquire's own error is returned verbatim")
    eq(released, 0, "with: release is never called when acquire fails")
    ok(not body_ran, "with: body never runs when acquire fails")
  end
end
