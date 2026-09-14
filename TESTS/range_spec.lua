-- TESTS/range_spec.lua — lib.lua.range

---@diagnostic disable: need-check-nil

return function(H)
  local eq, ok = H.eq, H.ok

  local range = require("lib.lua.range")

  local function joined(list)
    return table.concat(list, ",")
  end

  -- ------------------------------------------------------------------ happy

  do
    local list, err = range.parse("1-3,5,7")
    eq(err, nil, "parse: no error on a valid spec")
    eq(joined(list), "1,2,3,5,7", "parse: ranges expand, singles pass through, all sorted")
  end

  do
    local list = range.parse("5,5,1-3")
    eq(joined(list), "1,2,3,5", "parse: duplicates across a range and a single are deduplicated")
  end

  do
    local list = range.parse("3-1")
    eq(joined(list), "1,2,3", "parse: a reversed range (hi-lo) is normalized")
  end

  do
    local list = range.parse("  1 , 2-4 , 7 ")
    eq(joined(list), "1,2,3,4,7", "parse: whitespace around tokens is tolerated")
  end

  do
    local list = range.parse("42")
    eq(joined(list), "42", "parse: a single number spec")
  end

  do
    local list = range.parse("1-1")
    eq(joined(list), "1", "parse: a degenerate one-element range")
  end

  -- ------------------------------------------------------------------ empty/invalid

  do
    local list, err = range.parse("")
    eq(list, nil, "parse: empty spec returns nil")
    ok(err ~= nil, "parse: empty spec returns an error message")
  end

  do
    local list, err = range.parse("   ")
    eq(list, nil, "parse: whitespace-only spec returns nil")
    ok(err ~= nil, "parse: whitespace-only spec returns an error message")
  end

  do
    local list, err = range.parse("abc")
    eq(list, nil, "parse: non-numeric token returns nil")
    ok(err:match("abc") ~= nil, "parse: error message names the bad token")
  end

  do
    local list, err = range.parse("1,,3")
    eq(joined(list), "1,3", "parse: an empty token between commas is skipped, not an error")
    eq(err, nil, "parse: ...and does not report an error")
  end

  do
    local list, err = range.parse("1-3-5")
    eq(list, nil, "parse: a malformed range (two dashes) is rejected")
    ok(err ~= nil, "parse: ...with an error message")
  end

  do
    ---@diagnostic disable-next-line: param-type-mismatch
    local list, err = range.parse(nil)
    eq(list, nil, "parse: a non-string spec returns nil")
    ok(err ~= nil, "parse: ...with an error message")
  end

  -- ------------------------------------------------------------------- bounds

  do
    local list, err = range.parse("1-5", { max = 3 })
    eq(list, nil, "parse: a value above max is rejected")
    ok(err:match("above max") ~= nil, "parse: ...with a max-specific error")
  end

  do
    local list, err = range.parse("0-2", { min = 1 })
    eq(list, nil, "parse: a value below min is rejected")
    ok(err:match("below min") ~= nil, "parse: ...with a min-specific error")
  end

  do
    local list = range.parse("1-3", { min = 1, max = 3 })
    eq(joined(list), "1,2,3", "parse: a spec fully within [min, max] passes")
  end
end
