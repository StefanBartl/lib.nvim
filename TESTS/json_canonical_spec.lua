-- TESTS/json_canonical_spec.lua -- lib.nvim.json.canonical: the canonical encoder of the contract documents.

return function(H)
  local ok = H.ok

  ---Deep comparison (the shared `H.eq` compares references).
  local function eq(a, b, msg)
    if not vim.deep_equal(a, b) then
      error(("FAIL %s: expected %s, got %s"):format(msg or "", vim.inspect(b), vim.inspect(a)), 2)
    end
  end

  local function has(text, part, msg)
    ok(type(text) == "string" and text:find(part, 1, true), msg or ("expected " .. part))
  end

  local function lacks(text, part, msg)
    ok(not text:find(part, 1, true), msg or ("unexpected " .. part))
  end
  local json = require("lib.nvim.json.canonical")

  ---@param value any
  ---@return string|nil err
  local function fails(value)
    local good, err = pcall(json.encode, value)
    ok(not good, "expected an error")
    return tostring(err)
  end

  -- ── objects: sorted keys, whatever the insertion order ──
  local a = { zebra = 1, apple = 2, mango = { y = 1, x = 2 } }
  local b = {}
  b.mango = { x = 2, y = 1 }
  b.apple = 2
  b.zebra = 1
  eq(json.encode(a), '{"apple":2,"mango":{"x":2,"y":1},"zebra":1}', "keys sorted by byte value")
  eq(json.encode(a), json.encode(b), "insertion order does not matter")
  eq(
    json.encode({ B = 1, a = 2, ["_"] = 3 }),
    '{"B":1,"_":3,"a":2}',
    "byte order, not locale order"
  )

  -- Plain Lua 5.1 sorts with strcoll (the locale's collation), LuaJIT with bytes, so under LuaJIT the sort of the
  -- keys cannot show a locale at work. What can be shown: the comparator is the module's own bytewise one (a spy on
  -- `table.sort`, as long as the module sorts its keys with a bare `table.sort(keys)` this fails), and that
  -- comparator is right on the cases where strcoll and bytes part ways.
  local real_sort, comparators = table.sort, {}
  rawset(table, "sort", function(t, cmp)
    comparators[#comparators + 1] = cmp or false
    return real_sort(t, cmp)
  end)
  local sorted_ok, sorted_err = pcall(json.encode, { B = 1, Z = 2, ["_"] = 3, a = 4, b = 5 })
  rawset(table, "sort", real_sort)
  ok(sorted_ok, tostring(sorted_err))
  ok(#comparators > 0, "the keys of an object are sorted")
  for _, cmp in ipairs(comparators) do
    ok(
      cmp == json.bytes_less,
      "with the locale-independent comparator, not with the language's own <"
    )
  end

  local less = json.bytes_less
  ok(less("B", "a") and not less("a", "B"), "an upper case letter is before a lower case one")
  ok(less("Z", "_") and less("_", "a"), "Z, _, a: the order of the ASCII table")
  ok(less("a", "ab") and not less("ab", "a"), "a prefix is before the longer string")
  ok(less("", "a") and not less("a", ""), "the empty string is first")
  ok(less("a", "a\0") and not less("a\0", "a"), "a NUL byte counts, it does not end the string")
  ok(less("a\0", "a\0b") and less("a\0b", "a\1"), "a NUL inside a string is the lowest byte")
  ok(
    less("\195\164", "\200") and not less("\200", "\195\164"),
    "bytes above 127 by value, not by locale"
  )
  ok(not less("same", "same"), "irreflexive (table.sort needs it)")
  local words = { "b", "_", "a", "B", "Z", "ab", "a\0", "", "\200", "\195\164" }
  table.sort(words, less)
  eq(
    words,
    { "", "B", "Z", "_", "a", "a\0", "ab", "b", "\195\164", "\200" },
    "sorted by byte value"
  )
  eq(
    json.encode({ ["\200"] = 5, ab = 4, ["a\0"] = 3, a = 2, B = 1, ["\195\164"] = 6 }),
    '{"B":1,"a":2,"a\\u0000":3,"ab":4,"\195\164":6,"\239\191\189":5}',
    "NUL and high bytes in keys: the same order everywhere"
  )

  -- ── empty tables: the point of the whole module ──
  eq(json.encode({}), "[]", "an empty table is an array by default")
  eq(json.encode(json.object({})), "{}", "an object that is empty stays an object")
  eq(json.encode(json.array({})), "[]")
  eq(
    json.encode({ meta = json.object({}), tags = {} }),
    '{"meta":{},"tags":[]}',
    "the two kinds side by side"
  )
  eq(json.encode(json.object({ a = 1 })), '{"a":1}')
  eq(vim.json.encode({}), "[]", "(the reason this module exists)")

  -- Neovim's own empty-object marker is an object here too: decode -> encode must not turn {} into [].
  eq(json.encode(vim.empty_dict()), "{}", "vim.empty_dict() is an object")
  local roundtrip = '{"a":{},"b":[],"c":{"d":{}},"e":[{}],"params":{}}'
  eq(json.encode(vim.json.decode(roundtrip)), roundtrip, "decode -> encode keeps {} and [] apart")
  eq(json.encode(vim.json.decode("[]")), "[]", "a decoded [] stays an array")
  eq(json.encode(vim.json.decode("{}")), "{}", "a decoded {} stays an object")
  eq(json.encode(json.array(vim.empty_dict())), "[]", "an explicit array mark wins over the marker")
  eq(json.encode({ {}, vim.empty_dict() }), "[[],{}]", "unmarked {} is still an array")
  local with_key = vim.empty_dict()
  with_key.k = 1
  eq(json.encode(with_key), '{"k":1}', "a marked table with keys is an object, as before")
  local mixed = vim.empty_dict()
  mixed[1] = "x"
  has(fails(mixed), "mixes", "marked, but a list key")

  -- ── lists ──
  eq(json.encode({ 1, 2, 3 }), "[1,2,3]")
  eq(json.encode({ { 1, { "a" } }, {} }), '[[1,["a"]],[]]')
  eq(json.encode({ 1, vim.NIL, 3 }), "[1,null,3]", "vim.NIL is null (it fills a hole on purpose)")
  eq(json.encode({ true, false }), "[true,false]")

  -- ── numbers ──
  eq(
    json.encode({ 16, 16.0, 0, -0.0, -3 }),
    "[16,16,0,0,-3]",
    "whole numbers have no fraction, -0 is 0"
  )
  eq(json.encode({ 0.5, 2.5, 0.25 }), "[0.5,2.5,0.25]")
  eq(
    json.encode({ 0.1 + 0.2 }),
    "[0.30000000000000004]",
    "the fewest digits that read back as the same number"
  )
  eq(json.encode({ 1 / 3 }), "[0.3333333333333333]")
  eq(json.encode({ 1 / 7 }), "[0.14285714285714285]", "17 digits when 15 and 16 do not read back")
  eq(vim.json.decode(json.encode({ 0.1 + 0.2 }))[1], 0.1 + 0.2, "it reads back exactly")
  eq(json.encode({ 2 ^ 53 - 1 }), "[9007199254740991]", "the largest whole number that is exact")
  eq(json.encode({ -(2 ^ 53 - 1) }), "[-9007199254740991]", "and the same on the negative side")
  has(fails({ 2 ^ 53 }), "2^53 or more", "a whole number that would lose digits is an error")
  -- the exact texts: the limit holds for a negative number as it does for a positive one, and NaN, inf and -inf are
  -- told apart from a number that is only too big
  eq(
    fails({ 2 ^ 53 }),
    "json: $[1] is 9007199254740992, a whole number of 2^53 or more (digits would be lost)"
  )
  eq(
    fails({ -(2 ^ 53) }),
    "json: $[1] is -9007199254740992, a whole number of 2^53 or more (digits would be lost)",
    "the negative bound"
  )
  eq(
    fails({ -1e18 }),
    "json: $[1] is -1000000000000000000, a whole number of 2^53 or more (digits would be lost)",
    "far below the negative bound"
  )
  eq(fails({ math.huge }), "json: $[1] is inf; a contract has no NaN or inf", "inf")
  eq(fails({ -math.huge }), "json: $[1] is -inf; a contract has no NaN or inf", "-inf")
  has(fails({ 0 / 0 }), "NaN", "NaN")
  -- (how a platform prints NaN, `nan` or `-nan`, is not ours to pin)
  ok(
    fails({ 0 / 0 }):find("^json: %$%[1%] is [^;]+; a contract has no NaN or inf$"),
    "NaN, in full"
  )
  has(fails({ a = { b = { 0 / 0 } } }), "$.a.b[1]", "the error names the path")
  -- the path is only built for the error: it must still be the path of THIS value, not of a deeper sibling written
  -- before it, nor of the key that came before it at the same level
  eq(
    fails({ a = { { x = { y = { 1, 2 } } }, { z = 0 / 0 } } }):match("^json: (%S+)"),
    "$.a[2].z",
    "after a deeper sibling, the path has the right length"
  )
  eq(
    fails({ a = 1, b = { 1, 2, math.huge } }):match("^json: (%S+)"),
    "$.b[3]",
    "the key of the value, not the one before it"
  )
  eq(
    fails({ k = { { 1 }, { 2, { f = function() end } } } }):match("^json: (%S+)"),
    "$.k[2][2].f",
    "a value JSON cannot hold, deep down"
  )
  eq(
    fails({ k = { [true] = 1 } }):match("^json: (%S+)"),
    "$.k",
    "a bad key names the table that has it"
  )
  eq(
    fails({ x = { y = { json.memo({ { ok = 1 }, { n = 2 ^ 60 } }) } } }):match("^json: (%S+)"),
    "$.x.y[1][2].n",
    "the path runs on inside a memoised table"
  )

  -- ── strings ──
  eq(json.encode({ 'a"b\\c' }), '["a\\"b\\\\c"]')
  eq(json.encode({ "tab\there\nnew\rline" }), '["tab\\there\\nnew\\rline"]')
  eq(json.encode({ "\1\31" }), '["\\u0001\\u001f"]', "control bytes")
  eq(json.encode({ "a\127b" }), '["a\\u007fb"]', "DEL")
  eq(
    json.encode({ "a\194\155b\194\128" }),
    '["a\\u009bb\\u0080"]',
    "the C1 controls, CSI among them"
  )
  eq(json.encode({ "\194\159" }), '["\\u009f"]', "U+009F, the last of the C1 controls")
  eq(json.encode({ "\194\160" }), '["\194\160"]', "U+00A0 (no-break space) is no control")
  eq(
    json.encode({ "</script><!--" }),
    '["\\u003c/script>\\u003c!--"]',
    "safe inside a <script> block"
  )
  eq(json.encode({ "a\226\128\168b\226\128\169" }), '["a\\u2028b\\u2029"]', "U+2028 and U+2029")
  eq(
    json.encode({ "Größe 日本 \240\159\152\128" }),
    '["Größe 日本 \240\159\152\128"]',
    "valid UTF-8 is kept as it is"
  )
  local scrubbed = json.encode({ "a\255b" })
  eq(scrubbed, '["a\239\191\189b"]', "a bad byte becomes U+FFFD")
  eq(json.encode({ "\192\128" }), '["\239\191\189\239\191\189"]', "an overlong form is bad")
  eq(
    json.encode({ "\237\160\128" }),
    '["\239\191\189\239\191\189\239\191\189"]',
    "a surrogate is bad"
  )
  eq(
    json.encode({ "\224\128\128" }),
    '["\239\191\189\239\191\189\239\191\189"]',
    "an overlong 3-byte form is bad"
  )
  eq(
    json.encode({ "\240\128\128\128" }),
    '["\239\191\189\239\191\189\239\191\189\239\191\189"]',
    "an overlong 4-byte form is bad"
  )
  eq(
    json.encode({ "\244\144\128\128" }),
    '["\239\191\189\239\191\189\239\191\189\239\191\189"]',
    "everything above U+10FFFF is bad"
  )
  eq(
    json.encode({ "\245\128\128\128" }),
    '["\239\191\189\239\191\189\239\191\189\239\191\189"]',
    "a lead byte above F4 is bad"
  )
  eq(json.encode({ "\244\143\191\191" }), '["\244\143\191\191"]', "U+10FFFF itself is fine")
  -- both sides of every edge of the encoding: what is valid is kept byte for byte, what is not is replaced byte by byte
  local FFFD = "\239\191\189"
  for _, case in ipairs({
    { "U+07FF, the last 2-byte form", "\223\191" },
    { "U+0800, the first 3-byte form", "\224\160\128" },
    { "U+D7FF, just below the surrogates", "\237\159\191" },
    { "U+E000, just above the surrogates", "\238\128\128" },
    { "U+FFFD", "\239\191\189" },
    { "U+FFFF, the last 3-byte form", "\239\191\191" },
    { "U+10000, the first 4-byte form", "\240\144\128\128" },
  }) do
    eq(json.encode({ case[2] }), '["' .. case[2] .. '"]', case[1] .. " is kept")
  end
  for _, case in ipairs({
    { "E0 9F BF, an overlong 3-byte form", "\224\159\191", FFFD:rep(3) },
    { "F0 8F BF BF, an overlong 4-byte form", "\240\143\191\191", FFFD:rep(4) },
    { "C1 80, an overlong 2-byte form", "\193\128", FFFD:rep(2) },
    { "a lead byte followed by ASCII", "\195(", FFFD .. "(" },
    { "a lead byte followed by DEL", "\195\127", FFFD .. "\\u007f" },
    { "a lead byte followed by C0", "\195\192", FFFD:rep(2) },
    { "a 3-byte form cut off by ASCII", "\226\130(", FFFD:rep(2) .. "(" },
  }) do
    eq(json.encode({ case[2] }), '["' .. case[3] .. '"]', case[1] .. " is replaced")
  end
  eq(
    json.encode({ "ok\226\130" }),
    '["ok\239\191\189\239\191\189"]',
    "a cut-off sequence at the end"
  )
  ok(
    pcall(vim.json.decode, json.encode({ "x\255\254y" })),
    "whatever goes in, valid JSON comes out"
  )
  eq({ json.encode("") }, { '""' }, "an empty string")

  -- scrub_utf8: the text as the encoder holds it, before the escapes
  for _, text in ipairs({
    "",
    "plain",
    "Größe 日本 \240\159\152\128",
    "\244\143\191\191",
    'a\27b"<',
  }) do
    eq(json.scrub_utf8(text), text, "valid text is the same string: " .. vim.inspect(text))
  end
  eq(json.scrub_utf8("a\155b"), "a" .. FFFD .. "b", "a raw C1 byte")
  eq(json.scrub_utf8("\192\155"), FFFD:rep(2), "an overlong ESC")
  eq(json.scrub_utf8("\237\160\128"), FFFD:rep(3), "a surrogate")
  eq(json.scrub_utf8("ok\226\130"), "ok" .. FFFD:rep(2), "a cut-off sequence at the end")
  -- the valid stretches between bad bytes are copied whole: every byte of them, in place, none twice
  eq(
    json.scrub_utf8("\255Größe\254 日本 \253x\240\159\152\128\252"),
    FFFD .. "Größe" .. FFFD .. " 日本 " .. FFFD .. "x\240\159\152\128" .. FFFD,
    "bad bytes at the start, between valid text and at the end"
  )
  eq(json.scrub_utf8("\255\254"), FFFD:rep(2), "two bad bytes in a row")
  eq(json.scrub_utf8("ä\255"), "ä" .. FFFD, "a valid sequence right before a bad byte")
  local long_valid = ("abc äöü 日本 \240\159\152\128 "):rep(500)
  ok(rawequal(json.scrub_utf8(long_valid), long_valid), "long valid text: no copy is made")
  eq(
    json.scrub_utf8(long_valid .. "\255" .. long_valid),
    long_valid .. FFFD .. long_valid,
    "one bad byte in a long text"
  )

  -- ── escaped object keys are remembered across documents: a remembered key is the same text ──
  eq(json.encode({ ['a"<'] = 1 }), '{"a\\"\\u003c":1}', "a key that needs escapes")
  eq(json.encode({ ['a"<'] = 2 }), '{"a\\"\\u003c":2}', "and again, from the cache")
  eq(json.encode({ ['a"<'] = 3 }, { indent = 1 }), '{\n "a\\"\\u003c": 3\n}', "readable too")
  -- more distinct keys than the cache keeps: it starts over, and every key is still right
  local many, expect = {}, {}
  for i = 1, 3000 do
    many["k" .. i .. "\n"] = i
  end
  local many_keys = vim.tbl_keys(many)
  table.sort(many_keys, json.bytes_less)
  for i, k in ipairs(many_keys) do
    expect[i] = ('"%s":%d'):format(k:gsub("\n", "\\n"), many[k])
  end
  local many_text = "{" .. table.concat(expect, ",") .. "}"
  eq(json.encode(many), many_text, "3000 distinct keys")
  eq(json.encode(many), many_text, "and the same text a second time")

  -- ── what is no JSON is an error that says where ──
  has(fails({ 1, nil, 3 }), "not a list", "a hole")
  has(fails({ 1, 2, a = 3 }), "mixes", "a list that has a string key")
  has(fails({ [1.5] = true }), "key of type number", "a fractional key")
  has(fails(json.object({ 1, 2 })), "mixes", "an object with list keys")
  has(fails(json.array({ a = 1 })), "not a list", "an array mark does not make a string key a list")
  eq(json.encode(json.array({ 1, 2 })), "[1,2]", "and a list that is marked stays a list")
  has(fails({ f = function() end }), "$.f", "a function")
  local cycle = {}
  cycle[1] = cycle
  has(fails(cycle), "nested deeper", "a cycle fails instead of hanging")

  -- ── indent: the same document, readable ──
  local doc = { b = { 1, 2 }, a = json.object({}), c = {} }
  eq(
    json.encode(doc, { indent = 2 }),
    '{\n  "a": {},\n  "b": [\n    1,\n    2\n  ],\n  "c": []\n}',
    "empty containers stay on one line"
  )
  eq(vim.json.decode(json.encode(doc, { indent = 2 })).b, { 1, 2 }, "and it is the same JSON")
  lacks(json.encode(doc), "\n", "the compact form has no whitespace")
  lacks(json.encode(doc), " ")

  -- ── memo: the big part of a document is written once ──
  local big = json.memo({ { a = 1 }, { a = 2 } })
  local first = json.encode({ list = big, x = 1 })
  eq(first, '{"list":[{"a":1},{"a":2}],"x":1}')
  big[1].a = 99 -- (not allowed in real use; here it shows the text is remembered)
  eq(
    json.encode({ list = big, x = 2 }),
    '{"list":[{"a":1},{"a":2}],"x":2}',
    "the compact text is reused"
  )
  eq(
    json.encode({ list = big }, { indent = 1 }),
    '{\n "list": [\n  {\n   "a": 99\n  },\n  {\n   "a": 2\n  }\n ]\n}',
    "a readable document ignores the memo"
  )
  eq(json.encode(json.memo({})), "[]", "an empty memoised table is still an array")
  has(
    fails({ json.memo({ 0 / 0 }) }),
    "$[1][1]",
    "an error inside a memoised table names the full path"
  )

  -- the depth limit and the cycle guard hold across the memo boundary (a memoised table is rendered on its own)
  local function chain(wrappers, wrap)
    local d = {}
    for _ = 1, wrappers do
      d = wrap({ d })
    end
    return d
  end
  local function plain(t)
    return t
  end
  eq(
    #json.encode(chain(64, json.memo)),
    2 * 65,
    "64 wrappers of memoised tables: 65 levels, the most there is"
  )
  eq(#json.encode(chain(64, plain)), 2 * 65, "(the same for plain tables)")
  has(fails(chain(65, json.memo)), "nested deeper", "one level more fails, memoised")
  has(fails(chain(65, plain)), "nested deeper", "(and plain)")
  has(
    fails(chain(100, json.memo)),
    "nested deeper",
    "memoised or not does not decide whether a value is too deep"
  )
  local memo_cycle = json.memo({})
  memo_cycle[1] = memo_cycle
  local cycle_err = fails(memo_cycle)
  has(
    cycle_err,
    "nested deeper than 64 levels",
    "a cycle through a memoised table is the documented error"
  )
  has(cycle_err, "$[1][1]", "and it names the path")
  lacks(cycle_err, "stack overflow", "not the Lua stack limit")
  eq(fails(memo_cycle), cycle_err, "and again: a failed encode leaves no state behind")
  local inner = json.memo({})
  inner.a = { inner }
  has(fails({ w = inner }), "nested deeper", "a cycle that starts below the root")
  local left, right = json.memo({}), json.memo({})
  left[1], right[1] = right, left
  has(fails(left), "nested deeper", "a cycle through two memoised tables")
  local good_list = json.memo({ { a = 1 } })
  eq(
    json.encode({ list = good_list, x = 1 }),
    '{"list":[{"a":1}],"x":1}',
    "a memoised table below the root encodes"
  )
  eq(
    json.encode({ x = { good_list }, y = good_list }),
    '{"x":[[{"a":1}]],"y":[{"a":1}]}',
    "also when it is reused"
  )

  -- ── round trip through a real decoder ──
  local sample = {
    id = "lib.nvim/x",
    n = 4,
    ratio = 0.125,
    ok = true,
    tags = { "a", "b" },
    meta = json.object({}),
    none = vim.NIL,
  }
  local back = vim.json.decode(json.encode(sample))
  eq(back.id, "lib.nvim/x")
  eq(back.tags, { "a", "b" })
  eq(back.ratio, 0.125)
  eq(vim.json.encode(back.meta), "{}", "vim's own decoder keeps an empty object an object")
  ok(json.encode(sample):find('"meta":{}', 1, true), "the bytes are {}")
end
