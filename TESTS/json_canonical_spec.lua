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
  eq(json.encode({ 1 / 7 }), json.encode({ 1 / 7 }), "and the same every time")
  eq(vim.json.decode(json.encode({ 0.1 + 0.2 }))[1], 0.1 + 0.2, "it reads back exactly")
  eq(json.encode({ 2 ^ 53 - 1 }), "[9007199254740991]", "the largest whole number that is exact")
  has(fails({ 2 ^ 53 }), "2^53 or more", "a whole number that would lose digits is an error")
  has(fails({ 0 / 0 }), "NaN", "NaN")
  has(fails({ math.huge }), "inf", "inf")
  has(fails({ a = { b = { 0 / 0 } } }), "$.a.b[1]", "the error names the path")

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

  -- ── what is no JSON is an error that says where ──
  has(fails({ 1, nil, 3 }), "not a list", "a hole")
  has(fails({ 1, 2, a = 3 }), "mixes", "a list that has a string key")
  has(fails({ [1.5] = true }), "key of type number", "a fractional key")
  has(fails(json.object({ 1, 2 })), "mixes", "an object with list keys")
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
