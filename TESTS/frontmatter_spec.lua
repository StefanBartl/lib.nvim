-- TESTS/frontmatter_spec.lua — lib.nvim.markdown.frontmatter
--
-- The contract under test is "only the touched keys change": every other byte
-- of the text -- unknown keys, comments, blank lines, the body, the line
-- endings, the BOM -- must come back identical. So most assertions compare
-- whole strings, not parsed fields.

return function(H)
  local eq, ok = H.eq, H.ok
  local fm = require("lib.nvim.markdown.frontmatter")

  local BOM = "\239\187\191"

  --- Swap LF for CRLF.
  ---@param s string
  ---@return string
  local function crlf(s)
    return (s:gsub("\n", "\r\n"))
  end

  --- Parse, asserting it did not fail.
  ---@param text string
  ---@param opts? table
  ---@return table
  local function parse(text, opts)
    local p, err = fm.parse(text, opts)
    ok(p, "parse failed: " .. tostring(err))
    return p
  end

  --- update_text, asserting success.
  ---@param text string
  ---@param patch table
  ---@param opts? table
  ---@return string
  local function upd(text, patch, opts)
    local out, err = fm.update_text(text, patch, opts)
    ok(out, "update_text failed: " .. tostring(err))
    return out
  end

  local SAMPLE = table.concat({
    "---",
    "title: Picker items as their own source",
    "status: open",
    "# a comment line that must survive",
    "",
    "prio: 2",
    "tags: [pickers, ui]",
    "custom_field:   odd   spacing  ",
    "done: false",
    "---",
    "",
    "First paragraph.",
    "",
    "---",
    "",
    "key: not frontmatter",
    "",
  }, "\n")

  -- ----------------------------------------------------- roundtrip: byte-exact
  do
    eq(fm.serialize(parse(SAMPLE)), SAMPLE, "LF sample roundtrips")
    eq(fm.serialize(parse(crlf(SAMPLE))), crlf(SAMPLE), "CRLF sample roundtrips")
    eq(fm.serialize(parse(BOM .. SAMPLE)), BOM .. SAMPLE, "BOM sample roundtrips")
    eq(fm.serialize(parse(BOM .. crlf(SAMPLE))), BOM .. crlf(SAMPLE), "BOM + CRLF roundtrips")

    -- Mixed endings: each line keeps its own.
    local mixed = "---\r\na: 1\nb: 2\r\n---\nbody\r\n"
    eq(fm.serialize(parse(mixed)), mixed, "mixed line endings roundtrip")

    -- No trailing newline after the closing delimiter, and none in the body.
    local bare = "---\na: 1\n---"
    eq(fm.serialize(parse(bare)), bare, "closing delimiter at EOF roundtrips")
    local nobody = "---\na: 1\n---\nlast line without newline"
    eq(fm.serialize(parse(nobody)), nobody, "body without trailing newline roundtrips")

    -- Trailing whitespace on the delimiters.
    local ws = "---  \na: 1\n---\t\nbody\n"
    eq(fm.serialize(parse(ws)), ws, "whitespace after the delimiters roundtrips")

    -- A deterministic fuzz of delimiter-ish garbage: parse never throws and
    -- serialize(parse(t)) is always t.
    local alphabet =
      { "-", "-", "-", "\n", "\n", "\r", ":", " ", "#", "[", "]", '"', "'", "a", "1", "," }
    local seed = 12345
    local function rnd(n)
      seed = (seed * 1103515245 + 12345) % 2147483648
      return (seed % n) + 1
    end
    for _ = 1, 400 do
      local parts = {}
      if rnd(3) == 1 then
        parts[1] = "---\n"
      end
      for _ = 1, rnd(40) do
        parts[#parts + 1] = alphabet[rnd(#alphabet)]
      end
      local t = table.concat(parts)
      local p, err = fm.parse(t)
      ok(p, "fuzz parse failed: " .. tostring(err))
      eq(fm.serialize(p), t, "fuzz roundtrip of " .. vim.inspect(t))
    end
  end

  -- ------------------------------------------------------------------ parsing
  do
    local p = parse(SAMPLE)
    eq(p.has_block, true, "block found")
    eq(p.eol, "\n", "LF detected")
    eq(p.meta.title, "Picker items as their own source", "plain string")
    eq(p.meta.status, "open", "plain word")
    eq(p.meta.prio, "2", "a number-looking value stays a string")
    eq(type(p.meta.tags), "table", "inline list")
    eq(#p.meta.tags, 2, "two list items")
    eq(p.meta.tags[1], "pickers", "first item")
    eq(p.meta.tags[2], "ui", "second item")
    eq(p.meta.custom_field, "odd   spacing", "inner spacing kept, outer trimmed")
    eq(p.meta.done, false, "false is a boolean")
    eq(
      table.concat(p.order, ","),
      "title,status,prio,tags,custom_field,done",
      "file order, no comment/blank"
    )
    eq(
      p.body,
      "\nFirst paragraph.\n\n---\n\nkey: not frontmatter\n",
      "body starts right after the closing line"
    )
    eq(#p.raw_lines, 8, "raw_lines hold every block line incl. comment and blank")
    eq(p.raw_lines[3], "# a comment line that must survive", "raw line verbatim")
    eq(#p.warnings, 0, "comments and blank lines are not warnings")
    eq(fm.get(p, "status"), "open", "get")
    eq(fm.get(p, "nope"), nil, "get of an absent key")
    eq(fm.get(p, "nope", "dflt"), "dflt", "get with default")
    eq(fm.get(p, "done", true), false, "a stored false is not replaced by the default")

    eq(parse(crlf(SAMPLE)).eol, "\r\n", "CRLF detected")
    eq(
      parse(crlf(SAMPLE)).meta.title,
      "Picker items as their own source",
      "CRLF does not leak into values"
    )

    local b = parse(BOM .. SAMPLE)
    eq(b.bom, BOM, "BOM recorded")
    eq(b.has_block, true, "block found behind a BOM")
    eq(b.meta.status, "open", "values read behind a BOM")
  end

  -- ------------------------------------------------------------- value shapes
  do
    local p = parse(table.concat({
      "---",
      'dq: "has: colon and # hash"',
      "sq: 'it''s: fine # too'",
      'esc: "tab\\there \\"q\\" back\\\\slash"',
      "bool_t: true",
      "bool_f: false",
      'quoted_bool: "true"',
      "num: 42",
      "float: 1.5",
      "date: 2026-10-03",
      "empty:",
      "empty_list: []",
      "list: [a, 'b, c', \"d]e\", f g]",
      "trailing: value # a comment",
      "hash_inside: a#b",
      "url: https://example.com/x",
      'quoted_comment: "x" # note',
      "---",
      "",
    }, "\n"))
    local m = p.meta
    eq(m.dq, "has: colon and # hash", "double quoted with : and #")
    eq(m.sq, "it's: fine # too", "single quoted with '' and : and #")
    eq(m.esc, 'tab\there "q" back\\slash', "escapes")
    eq(m.bool_t, true, "true")
    eq(m.bool_f, false, "false")
    eq(m.quoted_bool, "true", "quoted true stays a string")
    eq(m.num, "42", "integer stays a string")
    eq(m.float, "1.5", "float stays a string")
    eq(m.date, "2026-10-03", "date stays a string")
    eq(m.empty, "", "empty value is the empty string")
    eq(#m.empty_list, 0, "empty list")
    eq(#m.list, 4, "list with quoted items")
    eq(m.list[2], "b, c", "comma inside a quoted item")
    eq(m.list[3], "d]e", "bracket inside a quoted item")
    eq(m.list[4], "f g", "plain item with a space")
    eq(m.trailing, "value", "trailing comment is not part of the value")
    eq(m.hash_inside, "a#b", "# without leading whitespace is data")
    eq(m.url, "https://example.com/x", "a colon inside a value")
    eq(m.quoted_comment, "x", "comment after a quoted value")
    eq(#p.warnings, 0, "no warnings for any of the above")

    local n =
      parse("---\nnum: 42\nfloat: -1.5\ndate: 2026-10-03\nword: 12abc\n---\n", { numbers = true })
    eq(n.meta.num, 42, "numbers = true reads integers")
    eq(n.meta.float, -1.5, "numbers = true reads floats")
    eq(n.meta.date, "2026-10-03", "dates are strings even with numbers = true")
    eq(n.meta.word, "12abc", "numbers = true does not eat 12abc")
  end

  -- -------------------------------------------- lines that are not understood
  do
    local text = table.concat({
      "---",
      "ok: yes",
      "no colon here",
      "key:nospace",
      "  indented: orphan",
      'broken: "unterminated',
      "list: [a, b",
      "map: {a: 1}",
      "block: |",
      "  multi",
      "  line",
      "tags:",
      "  - one",
      "  - two",
      "after: fine",
      "---",
      "body",
      "",
    }, "\n")
    local p = parse(text)
    eq(fm.serialize(p), text, "unparseable lines roundtrip verbatim")
    eq(p.meta.ok, "yes", "good line still read")
    eq(p.meta.after, "fine", "a good line after the junk is still read")
    eq(p.meta.broken, nil, "unterminated quote is not read")
    eq(p.meta.list, nil, "unterminated list is not read")
    eq(p.meta.map, nil, "flow map is not read")
    eq(p.meta.block, nil, "block scalar is not read")
    eq(p.meta.tags, nil, "nested block list is not read")
    ok(p.opaque.broken ~= nil, "unterminated quote is opaque")
    ok(p.opaque.block ~= nil, "block scalar is opaque")
    ok(p.opaque.tags ~= nil, "nested value is opaque")
    ok(#p.warnings >= 6, "each problem produces a warning")

    local out, err = fm.update_text(text, { tags = { "x" } })
    eq(out, nil, "an opaque key is not rewritten")
    ok(err and err:find("tags", 1, true), "the error names the key")
    local out2 = upd(text, { ok = "no" })
    eq(
      out2,
      text:gsub("ok: yes", "ok: no", 1),
      "other keys can still be patched next to opaque ones"
    )
  end

  -- ----------------------------------------------------------- no block / empty
  do
    local plain = "# Heading\n\nSome text\n---\nkey: value\n---\n"
    local p = parse(plain)
    eq(p.has_block, false, "no block")
    eq(p.unterminated, false, "not unterminated either")
    eq(p.body, plain, "body is the whole text")
    eq(next(p.meta), nil, "no meta")
    eq(fm.serialize(p), plain, "no-block roundtrip")

    local lead_blank = "\n---\na: 1\n---\n"
    eq(parse(lead_blank).has_block, false, "a block must start on the first line")

    local empty = parse("")
    eq(empty.has_block, false, "empty text has no block")
    eq(fm.serialize(empty), "", "empty text roundtrips")

    local unterminated = "---\na: 1\nno closing line\n"
    local u = parse(unterminated)
    eq(u.has_block, false, "an unclosed block is not a block")
    eq(u.unterminated, true, "but it is flagged")
    eq(u.body, unterminated, "body is the whole text")
    eq(#u.warnings, 1, "one warning")
    eq(fm.serialize(u), unterminated, "unterminated roundtrip")
    local out, err = fm.update_text(unterminated, { b = "2" }, { create = true })
    eq(out, nil, "no second block on top of an unclosed one")
    ok(err, "with a reason")

    local single = "---"
    eq(parse(single).has_block, false, "a lone delimiter is not a block")

    -- Empty block.
    local eb = parse("---\n---\nbody\n")
    eq(eb.has_block, true, "empty block found")
    eq(#eb.order, 0, "no keys")
    eq(eb.body, "body\n", "body after an empty block")
    eq(
      upd("---\n---\nbody\n", { a = "1" }),
      "---\na: 1\n---\nbody\n",
      "key added to an empty block"
    )
    eq(
      upd("---\r\n---\r\nbody\r\n", { a = "1" }),
      "---\r\na: 1\r\n---\r\nbody\r\n",
      "CRLF empty block"
    )

    -- A "---" or "key: x" in the body is just body.
    local with_body = "---\na: 1\n---\nb: 2\n---\nc: 3\n"
    local wb = parse(with_body)
    eq(wb.meta.a, "1", "block key read")
    eq(wb.meta.b, nil, "body line is not a key")
    eq(wb.body, "b: 2\n---\nc: 3\n", "body keeps its own ---")
    eq(
      upd(with_body, { a = "9" }),
      "---\na: 9\n---\nb: 2\n---\nc: 3\n",
      "body byte-identical after update"
    )
  end

  -- ------------------------------------------------------------------ updating
  do
    -- Only the touched line changes.
    eq(
      upd(SAMPLE, { status = "doing" }),
      (SAMPLE:gsub("status: open", "status: doing", 1)),
      "one key changed, every other byte identical"
    )
    eq(
      upd(crlf(SAMPLE), { status = "doing" }),
      crlf((SAMPLE:gsub("status: open", "status: doing", 1))),
      "same under CRLF"
    )
    eq(
      upd(BOM .. SAMPLE, { status = "doing" }),
      BOM .. (SAMPLE:gsub("status: open", "status: doing", 1)),
      "same behind a BOM"
    )

    -- Equal value: nothing touched, not even the quote style.
    local quoted = '---\nstatus: "open"\n---\n'
    eq(upd(quoted, { status = "open" }), quoted, "equal value leaves the line alone")
    eq(upd(SAMPLE, {}), SAMPLE, "empty patch is a no-op")

    -- Unknown keys, comments and blank lines survive a patch of another key.
    local out = upd(SAMPLE, { prio = "1" })
    ok(
      out:find("custom_field:   odd   spacing  \n", 1, true),
      "unknown key line untouched, spacing and all"
    )
    ok(
      out:find("# a comment line that must survive\n\nprio: 1\n", 1, true),
      "comment and blank line untouched"
    )

    -- Appended key: after the last block line, before the closing ---.
    eq(
      upd(SAMPLE, { created = "2026-10-03" }),
      (SAMPLE:gsub("done: false\n%-%-%-\n", "done: false\ncreated: 2026-10-03\n---\n", 1)),
      "new key is appended at the end of the block"
    )
    eq(
      upd(crlf(SAMPLE), { created = "2026-10-03" }),
      crlf((SAMPLE:gsub("done: false\n%-%-%-\n", "done: false\ncreated: 2026-10-03\n---\n", 1))),
      "appended line uses the file's CRLF"
    )

    -- Several new keys: a map is applied in sorted order, a pair list in the given order.
    eq(
      upd("---\na: 1\n---\n", { zeta = "z", alpha = "a" }),
      "---\na: 1\nalpha: a\nzeta: z\n---\n",
      "map patch: deterministic sorted order"
    )
    eq(
      upd("---\na: 1\n---\n", { { "zeta", "z" }, { "alpha", "a" } }),
      "---\na: 1\nzeta: z\nalpha: a\n---\n",
      "pair-list patch: given order"
    )

    -- Types.
    eq(upd("---\n---\n", { b = true }), "---\nb: true\n---\n", "boolean")
    eq(upd("---\n---\n", { b = false }), "---\nb: false\n---\n", "false is a value, not a removal")
    eq(upd("---\n---\n", { n = 3 }), "---\nn: 3\n---\n", "integer")
    eq(upd("---\n---\n", { n = 0.5 }), "---\nn: 0.5\n---\n", "float")
    eq(upd("---\n---\n", { l = { "a", "b c" } }), "---\nl: [a, b c]\n---\n", "list")
    eq(upd("---\n---\n", { l = {} }), "---\nl: []\n---\n", "empty list")
    eq(
      upd("---\n---\n", { l = { 1, true } }),
      '---\nl: [1, "true"]\n---\n',
      "list items are strings"
    )
    eq(
      upd("---\ntags: [a]\n---\n", { tags = { "a", "b" } }),
      "---\ntags: [a, b]\n---\n",
      "list rewritten in place"
    )

    -- Rewriting keeps a trailing comment.
    eq(
      upd("---\nstatus: open # why\n---\n", { status = "done" }),
      "---\nstatus: done # why\n---\n",
      "trailing comment survives a rewrite"
    )

    -- Rewriting a value that was quoted.
    eq(
      upd('---\nstatus: "open"\n---\n', { status = "done" }),
      "---\nstatus: done\n---\n",
      "new value is written plain when it can be"
    )

    -- Removal.
    eq(
      upd(SAMPLE, { prio = fm.REMOVE }),
      (SAMPLE:gsub("prio: 2\n", "", 1)),
      "REMOVE deletes exactly that line"
    )
    eq(upd(SAMPLE, { nope = fm.REMOVE }), SAMPLE, "removing an absent key is a no-op")
    eq(
      upd(crlf(SAMPLE), { prio = vim.NIL }),
      crlf((SAMPLE:gsub("prio: 2\n", "", 1))),
      "vim.NIL is the same as REMOVE, CRLF kept"
    )
    eq(
      upd("---\na: 1\na: 2\nb: 3\n---\n", { a = fm.REMOVE }),
      "---\nb: 3\n---\n",
      "REMOVE drops every line of a duplicated key"
    )
    eq(
      upd("---\na: 1\n---\nbody\n", { a = fm.REMOVE }),
      "---\n---\nbody\n",
      "removing the last key keeps an empty block"
    )
    eq(
      upd("body\n", { a = fm.REMOVE }),
      "body\n",
      "removal from a text without a block does nothing"
    )

    -- Duplicate keys: the effective (last) one is rewritten.
    local dup = parse("---\na: 1\na: 2\n---\n")
    eq(dup.meta.a, "2", "last duplicate wins")
    eq(#dup.order, 1, "listed once")
    eq(#dup.warnings, 1, "duplicate warned about")
    eq(
      upd("---\na: 1\na: 2\n---\n", { a = "9" }),
      "---\na: 1\na: 9\n---\n",
      "last duplicate is the one rewritten"
    )

    -- Values that must be quoted to stay what they are, read back identical.
    local tricky = {
      "a: b",
      "x #y",
      "true",
      "False",
      "null",
      "~",
      "",
      " padded ",
      "[x]",
      "{x}",
      'say "hi"',
      "line\nbreak",
      "tab\there",
      "back\\slash",
      "it's",
      "# not a comment",
      "- dash",
      "-5",
      "&anchor",
      "*alias",
      "!tag",
      "trailing:",
      "@at",
      "100%",
      "%percent",
      "a,b",
      "ünïcode ✓",
    }
    for _, v in ipairs(tricky) do
      local text = upd("---\n---\n", { k = v })
      local back = parse(text)
      eq(back.meta.k, v, "string survives a write/read cycle: " .. vim.inspect(v))
      eq(#back.warnings, 0, "no warnings for " .. vim.inspect(v))
      eq(#vim.split(text, "\n", { plain = true }), 4, "one line per value: " .. vim.inspect(v))
      -- And a second identical patch is a no-op.
      eq(upd(text, { k = v }), text, "idempotent for " .. vim.inspect(v))
    end
    -- Plain strings stay plain.
    eq(
      upd("---\n---\n", { k = "simple value" }),
      "---\nk: simple value\n---\n",
      "no needless quotes"
    )
    eq(
      upd("---\n---\n", { k = "https://x.y/z?a=1" }),
      "---\nk: https://x.y/z?a=1\n---\n",
      "URL stays plain"
    )
    eq(upd("---\n---\n", { k = "2026-10-03" }), "---\nk: 2026-10-03\n---\n", "date stays plain")

    -- List items that need quoting.
    local lt = upd("---\n---\n", { l = { "a,b", "c]", "d", "", "it's", "x: y" } })
    local lp = parse(lt)
    eq(#lp.meta.l, 6, "six items")
    eq(lp.meta.l[1], "a,b", "comma in item")
    eq(lp.meta.l[2], "c]", "bracket in item")
    eq(lp.meta.l[4], "", "empty item kept")
    eq(lp.meta.l[5], "it's", "apostrophe in item")
    eq(lp.meta.l[6], "x: y", "colon in item")

    -- numbers = true: meta tracks what the file now says.
    local np = parse("---\nn: 1\n---\n", { numbers = true })
    ok(fm.set(np, "n", 7))
    eq(np.meta.n, 7, "number in meta under numbers = true")
    eq(fm.serialize(np), "---\nn: 7\n---\n", "number written")
    local sp = parse("---\nn: 1\n---\n")
    ok(fm.set(sp, "n", 7))
    eq(sp.meta.n, "7", "number reads back as a string by default")
  end

  -- ------------------------------------------------------ add a block / create
  do
    local body = "# Title\n\ntext\n"
    eq(
      upd(body, { title = "T", status = "open" }, { create = true }),
      "---\nstatus: open\ntitle: T\n---\n# Title\n\ntext\n",
      "create = true adds a block in front, body untouched"
    )
    eq(
      upd(crlf(body), { a = "1" }, { create = true }),
      "---\r\na: 1\r\n---\r\n" .. crlf(body),
      "created block matches the file's CRLF"
    )
    eq(
      upd(BOM .. body, { a = "1" }, { create = true }),
      BOM .. "---\na: 1\n---\n" .. body,
      "created block goes after the BOM"
    )
    eq(upd("", { a = "1" }, { create = true }), "---\na: 1\n---\n", "block in an empty text")

    local out, err = fm.update_text(body, { a = "1" })
    eq(out, nil, "no block, no create: refused")
    ok(err and err:find("create", 1, true), "the error says how to proceed")
    eq(
      upd(body, { a = fm.REMOVE }, { create = true }),
      body,
      "create does not add a block for removals only"
    )

    eq(fm.add_block(body, { a = "1" }), "---\na: 1\n---\n" .. body, "add_block")
    eq(fm.add_block(body), "---\n---\n" .. body, "add_block without meta makes an empty block")
    local again, aerr = fm.add_block("---\na: 1\n---\n", { b = "2" })
    eq(again, nil, "add_block refuses when a block exists")
    ok(aerr, "with a reason")
  end

  -- ------------------------------------------------------------ bad input / errors
  do
    local p, err = fm.parse(nil)
    eq(p, nil, "parse(nil) does not throw")
    ok(err, "and says why")
    eq(select(1, fm.parse(42)), nil, "parse(number) does not throw")
    eq(select(1, fm.update_text(nil, { a = "1" })), nil, "update_text(nil) does not throw")

    -- Binary junk.
    local junk = "---\n\0\1\2: \255\254\n---\n\0"
    local jp = parse(junk)
    eq(fm.serialize(jp), junk, "binary junk roundtrips")

    local base = "---\na: 1\n---\nbody\n"
    local bad = {
      { { ["bad key"] = "x" }, "key with a space" },
      { { [""] = "x" }, "empty key" },
      { { [":x"] = "x" }, "key starting with a colon" },
      { { a = function() end }, "function value" },
      { { a = { x = 1 } }, "map value" },
      { { a = { { 1 } } }, "nested list" },
      { { a = 0 / 0 }, "NaN" },
      { { a = math.huge }, "inf" },
      { { a = "bad\1control" }, "control character" },
      { { [1] = "x" }, "non-pair list entry" },
      { { { "k" } }, "pair without a value" },
      { "a=1", "patch that is not a table" },
    }
    for _, case in ipairs(bad) do
      local out, e = fm.update_text(base, case[1])
      eq(out, nil, "refused: " .. case[2])
      ok(type(e) == "string" and e ~= "", "reason given: " .. case[2])
    end

    -- All or nothing: a bad second entry leaves the parse untouched.
    local pp = parse(base)
    local okp, perr = fm.patch(pp, { { "a", "changed" }, { "b c", "bad" } })
    eq(okp, false, "patch with a bad entry fails")
    ok(perr, "with a reason")
    eq(fm.serialize(pp), base, "and changed nothing")
    eq(pp.meta.a, "1", "meta untouched too")

    local nok = fm.patch(nil, { a = "1" })
    eq(nok, false, "patch on a non-parse does not throw")
  end

  -- -------------------------------------------------------------------- files
  do
    local path = H.tmpfile(".md")
    --- Write bytes exactly.
    ---@param p string
    ---@param s string
    local function put(p, s)
      local f = assert(io.open(p, "wb"))
      f:write(s)
      f:close()
    end
    --- Read bytes exactly.
    ---@param p string
    ---@return string
    local function get(p)
      local f = assert(io.open(p, "rb"))
      local s = f:read("*a")
      f:close()
      return s
    end

    local text = crlf(SAMPLE):gsub("\r\n$", "") -- CRLF file whose last line has no newline
    put(path, text)

    local rp, rerr = fm.read(path)
    ok(rp, "read failed: " .. tostring(rerr))
    eq(rp.meta.status, "open", "read parses the file")
    eq(rp.eol, "\r\n", "read sees CRLF")

    local uok, uerr = fm.update(path, { status = "doing", created = "2026-10-03" })
    ok(uok, "update failed: " .. tostring(uerr))
    local expected =
      text
        :gsub("status: open", "status: doing", 1)
        :gsub("done: false\r\n%-%-%-\r\n", "done: false\r\ncreated: 2026-10-03\r\n---\r\n", 1)
    eq(get(path), expected, "file updated byte-exactly (CRLF, no trailing newline kept)")
    eq(vim.fn.glob(path .. ".frontmatter.*"), "", "no temp file left behind")

    -- Unchanged patch: no write at all (the file is left alone).
    local before = vim.uv.fs_stat(path)
    local nok2, nerr2 = fm.update(path, { status = "doing" })
    ok(nok2, "no-op update failed: " .. tostring(nerr2))
    local after = vim.uv.fs_stat(path)
    eq(after.mtime.sec, before.mtime.sec, "mtime unchanged by a no-op update")
    eq(after.mtime.nsec, before.mtime.nsec, "mtime nsec unchanged by a no-op update")
    eq(get(path), expected, "content unchanged by a no-op update")

    -- Create a block in a file without one.
    local plain = H.tmpfile(".md")
    put(plain, "just text, no newline at end")
    ok(fm.update(plain, { a = "1" }, { create = true }))
    eq(
      get(plain),
      "---\na: 1\n---\njust text, no newline at end",
      "block created, text kept byte-exact"
    )
    local refused, rerr2 = fm.update(plain, { b = "1" }, { create = false })
    eq(refused, true, "a file that has the block now: plain update works")
    ok(not rerr2, "without error")

    local nofile = H.tmpfile(".md")
    local mr, mre = fm.read(nofile)
    eq(mr, nil, "read of a missing file")
    ok(mre, "returns an error")
    local mu, mue = fm.update(nofile, { a = "1" }, { create = true })
    eq(mu, false, "update of a missing file")
    ok(mue, "returns an error")

    os.remove(path)
    os.remove(plain)
  end

  -- ------------------------------------------- numbers mode: strings survive
  do
    local p = parse("---\na: 1\n---\n", { numbers = true })
    for _, v in ipairs({ "42", "007", "-3", "1.5", ".5" }) do
      ok(fm.set(p, "s", v), "set failed for " .. v)
      eq(p.meta.s, v, "meta keeps the string " .. v)
      local back = parse(fm.serialize(p), { numbers = true })
      eq(back.meta.s, v, "a re-read yields the same string " .. v)
      eq(type(back.meta.s), "string", "still a string " .. v)
    end
    -- A real number stays a bare number in that mode.
    ok(fm.set(p, "n", 7), "set number")
    eq(parse(fm.serialize(p), { numbers = true }).meta.n, 7, "number roundtrips as number")
    -- Without the mode nothing changes: the string is written bare.
    eq(
      upd("---\na: 1\n---\n", { s = "42" }),
      "---\na: 1\ns: 42\n---\n",
      "default mode writes it bare"
    )
  end

  -- ------------------------------------- prose between two `---` is no block
  do
    local text = "---\nSome text\n---\n"
    local p = parse(text)
    eq(p.prose, true, "prose block is flagged")
    local out, err = fm.update_text(text, { c = "1" }, { create = true })
    eq(out, nil, "patching prose is refused")
    ok(err and err:find("prose"), "error names the reason")
    eq(fm.serialize(p), text, "parse still roundtrips byte-exactly")
    -- Mixed blocks and empty blocks are still patchable.
    eq(parse("---\na: 1\nstray\n---\n").prose, false, "a block with keys is not prose")
    eq(parse("---\n---\n").prose, false, "an empty block is not prose")
    eq(upd("---\n---\n", { c = "1" }), "---\nc: 1\n---\n", "empty block patchable")
    eq(
      upd("---\na: 1\nstray\n---\n", { c = "1" }),
      "---\na: 1\nstray\nc: 1\n---\n",
      "mixed block patchable"
    )
  end

  -- ------------------------------------------- temp name is unique per write
  do
    local path = H.tmpfile(".md")
    local f = assert(io.open(path, "wb"))
    f:write("---\na: 1\n---\n")
    f:close()
    -- A leftover temp file under the old fixed name must neither break nor be
    -- reused by the next write.
    local stale = path .. ".frontmatter.tmp"
    local sf = assert(io.open(stale, "wb"))
    sf:write("stale")
    sf:close()
    ok(fm.update(path, { a = "2" }), "update beside a stale temp file")
    local rf = assert(io.open(stale, "rb"))
    eq(rf:read("*a"), "stale", "the fixed legacy temp name is not touched")
    rf:close()
    os.remove(stale)
    os.remove(path)
  end

  -- ------------------ a long whitespace run is read in linear time (SEC-32)
  -- `s:gsub("%s+$", "")`, `s:match("^%s*(.-)%s*$")` and `s:find("%s+#")` retry
  -- the rest of a whitespace run from every byte inside it: 40 000 spaces took
  -- ~6 s, 160 000 took ~100 s, on a single line. 200 000 spaces would run for
  -- minutes with the old code, so the bound below fails loudly instead of flaking.
  do
    local run = (" "):rep(200000)
    local limit_ms = 3000

    ---@param label string
    ---@param text string
    ---@return table
    local function timed_parse(label, text)
      local t0 = vim.uv.hrtime()
      local p = parse(text)
      local ms = (vim.uv.hrtime() - t0) / 1e6
      ok(ms < limit_ms, ("%s took %.0f ms (limit %d)"):format(label, ms, limit_ms))
      eq(fm.serialize(p), text, label .. ": still byte-exact")
      return p
    end

    local p = timed_parse("run inside a plain value", "---\ntitle: a" .. run .. "b\n---\n")
    eq(p.meta.title, "a" .. run .. "b", "the inner run stays part of the value")

    p = timed_parse("trailing run after a plain value", "---\ntitle: abc" .. run .. "\n---\n")
    eq(p.meta.title, "abc", "trailing whitespace is trimmed")

    p = timed_parse("run before a comment", "---\ntitle: abc" .. run .. "# not a comment\n---\n")
    eq(p.meta.title, "abc", "a whitespace run followed by # starts the comment")
    eq(p.by_key.title.comment, run .. "# not a comment", "the comment keeps its leading run")

    p = timed_parse("run inside a list item", "---\ntags: [a" .. run .. "b, c" .. run .. "]\n---\n")
    eq(#p.meta.tags, 2, "two list items")
    eq(p.meta.tags[1], "a" .. run .. "b", "inner run of a list item kept")
    eq(p.meta.tags[2], "c", "trailing run of a list item trimmed")

    p = timed_parse("value is only whitespace", "---\ntitle:" .. run .. "\n---\n")
    eq(p.meta.title, "", "an empty value")

    -- The comment search keeps its meaning on ordinary input: the value ends
    -- at the first whitespace run that is directly followed by `#`.
    local cases = {
      { "abc # note", "abc", " # note" },
      { "abc  \t# note   ", "abc", "  \t# note" },
      { "a#b # c", "a#b", " # c" },
      { "a #b #c", "a", " #b #c" },
      { "x#y", "x#y", nil },
    }
    for _, c in ipairs(cases) do
      local q = parse("---\nk: " .. c[1] .. "\n---\n")
      eq(q.meta.k, c[2], "value of " .. c[1])
      eq(q.by_key.k.comment, c[3], "comment of " .. c[1])
    end
    -- A value that starts with `#` is a comment on an empty value.
    eq(parse("---\nk: #lead\n---\n").meta.k, "", "a value starting with # is empty")
  end
end
