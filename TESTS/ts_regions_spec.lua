-- TESTS/ts_regions_spec.lua — lib.nvim.treesitter.regions: capture name -> ranges, fail-open.

return function(H)
  local eq, ok = H.eq, H.ok
  local regions = require("lib.nvim.treesitter.regions")

  if not pcall(vim.treesitter.language.add, "lua") then
    H.skipped("treesitter.regions", "no lua parser on this host")
    return
  end

  local function lua_buf(lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "lua"
    return buf
  end

  -- captures of the language's highlights query, as byte ranges
  local buf = lua_buf({ 'local s = "hi"', "-- a comment", "local n = 1" })
  local found, why = regions.collect(buf, { "string", "comment" })
  ok(found ~= nil, "collect: found something (" .. tostring(why) .. ")")
  eq(why, nil, "collect: no reason when it worked")
  ok(#found.string >= 1, "collect: the string capture")
  eq(#found.comment, 1, "collect: the comment capture")

  local c = found.comment[1]
  eq(c[1], 1, "comment: start row (0-based)")
  eq(c[2], 0, "comment: start column")
  eq(c[3], 1, "comment: end row")
  eq(c[4], 12, "comment: end column, exclusive")
  eq(c.start_byte, #'local s = "hi"' + 1, "comment: start byte offset in the buffer")
  eq(c.end_byte - c.start_byte, #"-- a comment", "comment: length in bytes")
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  eq(
    text:sub(c.start_byte + 1, c.end_byte),
    "-- a comment",
    "comment: the byte range slices the comment out"
  )

  -- position predicates (end exclusive)
  eq(regions.contains(found.comment, 1, 0), true, "contains: first column")
  eq(regions.contains(found.comment, 1, 11), true, "contains: last column")
  eq(regions.contains(found.comment, 1, 12), false, "contains: end is exclusive")
  eq(regions.contains(found.comment, 0, 5), false, "contains: another row")
  eq(regions.contains_pos(found.comment, 2, 1), true, "contains_pos: 1-based")
  eq(regions.contains_pos(found.comment, 3, 1), false, "contains_pos: outside")
  eq(regions.contains_byte(found.comment, c.start_byte), true, "contains_byte: first byte")
  eq(regions.contains_byte(found.comment, c.end_byte), false, "contains_byte: end exclusive")
  eq(#regions.byte_ranges(found.comment), 1, "byte_ranges: one pair per range")
  eq(regions.byte_ranges(found.comment)[1][1], c.start_byte, "byte_ranges: start")
  eq(regions.byte_ranges(found.comment)[1][2], c.end_byte, "byte_ranges: end")

  -- a defined capture that matches nothing is an empty list, an undefined one is absent
  local plain = lua_buf({ "local n = 1" })
  local f2 = regions.collect(plain, { "comment", "string", "no_such_capture_xyz" })
  ok(f2 ~= nil, "empty match: still region info")
  eq(#f2.comment, 0, "empty match: a defined capture without nodes is an empty list")
  eq(f2.no_such_capture_xyz, nil, "an undefined capture is absent from the map")

  -- exact names by default; `hierarchical` also takes the dotted children. A prefix that has dotted children
  -- in this parser's query but no capture of its own name:
  local hq = vim.treesitter.query.get("lua", "highlights")
  local own, child = {}, nil
  for _, cap in ipairs(hq.captures) do
    own[cap] = true
  end
  for _, cap in ipairs(hq.captures) do
    local parent = cap:match("^(.*)%.[^.]+$")
    if parent and not own[parent] then
      child = { parent = parent, name = cap }
      break
    end
  end
  if child then
    local hbuf = lua_buf({ "local function f() return { 1, 2 } end", "-- c", '"x"' })
    local exact = regions.collect(hbuf, { child.parent })
    eq(exact, nil, "exact: `" .. child.parent .. "` does not collect `" .. child.name .. "`")
    local deep, deep_why = regions.collect(hbuf, { child.parent }, { hierarchical = true })
    ok(
      deep ~= nil,
      "hierarchical: the parent collects its dotted children (" .. tostring(deep_why) .. ")"
    )
    local direct = regions.collect(hbuf, { child.name }, { hierarchical = true })
    ok(
      direct ~= nil and #direct[child.name] >= 0,
      "hierarchical: the specific name is still itself"
    )
    local both = regions.collect(hbuf, { child.parent, child.name }, { hierarchical = true })
    ok(
      both ~= nil and both[child.name] ~= nil and both[child.parent] ~= nil,
      "hierarchical: both names are keys"
    )
    eq(
      #deep[child.parent],
      #both[child.parent] + #both[child.name],
      "hierarchical: the most specific requested name owns a node, once"
    )
  else
    H.skipped(
      "treesitter.regions hierarchical",
      "the lua highlights query has no dotted capture without a parent"
    )
  end

  -- row window
  local f3 = regions.collect(buf, { "comment" }, { first_row = 0, last_row = 1 })
  eq(#f3.comment, 0, "first_row/last_row: the comment is outside rows 0..1")
  local f4 = regions.collect(buf, { "comment" }, { first_row = 1, last_row = 2 })
  eq(#f4.comment, 1, "first_row/last_row: ... and inside rows 1..2")

  -- fail-open: nil plus a reason, never an error
  local none, r1 = regions.collect(buf, { "no_such_capture_xyz" })
  eq(none, nil, "no defined capture: nil")
  eq(r1, "capture_not_defined", "no defined capture: the reason")

  local bare = vim.api.nvim_create_buf(false, true)
  local n2, r2 = regions.collect(bare, { "comment" })
  eq(n2, nil, "no filetype: nil")
  eq(r2, "no_filetype", "no filetype: the reason")

  local weird = vim.api.nvim_create_buf(false, true)
  vim.bo[weird].filetype = "nosuchlangxyz"
  local n3, r3 = regions.collect(weird, { "comment" })
  eq(n3, nil, "unknown language: nil")
  eq(r3, "no_parser", "unknown language: no parser")

  local n4, r4 = regions.collect(buf, { "comment" }, { query = "nosuchquerygroupxyz" })
  eq(n4, nil, "unknown query group: nil")
  eq(r4, "no_query", "unknown query group: the reason")

  local n5, r5 = regions.collect(99999, { "comment" })
  eq(n5, nil, "invalid buffer: nil")
  eq(r5, "invalid_buffer", "invalid buffer: the reason")

  -- an explicit language overrides the filetype
  local n6 = regions.collect(bare, { "comment" }, { lang = "lua" })
  eq(type(n6), "table", "explicit lang: regions without a filetype")
end
