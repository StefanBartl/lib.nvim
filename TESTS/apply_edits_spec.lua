-- TESTS/apply_edits_spec.lua — lib.nvim.buffer.apply_edits

return function(H)
  local eq, ok = H.eq, H.ok

  local apply_edits = require("lib.nvim.buffer.apply_edits")

  local function new_buf(lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    return buf
  end

  local function get_lines(buf)
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end

  local function joined(list)
    return table.concat(list, ",")
  end

  -- ------------------------------------------------------------- bottom-up

  -- Two edits on the same line, computed against the original buffer. If
  -- applied top-to-bottom naively, the first edit shifts the second edit's
  -- column out from under it. Bottom-up must get this right.
  do
    local buf = new_buf({ "aaa bbb ccc" })
    local result = apply_edits(buf, {
      { start_row = 0, start_col = 0, end_row = 0, end_col = 3, text = { "XXXXXXXXXX" } }, -- "aaa" -> long text
      { start_row = 0, start_col = 8, end_row = 0, end_col = 11, text = { "ZZZ" } }, -- "ccc" -> "ZZZ"
    })
    eq(result.applied, 2, "bottom-up: both edits applied")
    eq(#result.skipped, 0, "bottom-up: nothing skipped")
    eq(
      get_lines(buf)[1],
      "XXXXXXXXXX bbb ZZZ",
      "bottom-up: the later edit's position survives the earlier one's shift"
    )
  end

  -- Multi-line: an edit on an earlier line must not be corrupted by a later
  -- edit on a line below it, applied in the same batch.
  do
    local buf = new_buf({ "line one", "line two", "line three" })
    local result = apply_edits(buf, {
      { start_row = 0, start_col = 5, end_row = 0, end_col = 8, text = { "1" } },
      { start_row = 2, start_col = 5, end_row = 2, end_col = 10, text = { "3" } },
    })
    eq(result.applied, 2, "multi-line: both edits applied")
    eq(joined(get_lines(buf)), "line 1,line two,line 3", "multi-line: both edits landed correctly")
  end

  -- ---------------------------------------------------------- stale-match

  do
    local buf = new_buf({ "hello world" })
    local result = apply_edits(buf, {
      {
        start_row = 0,
        start_col = 6,
        end_row = 0,
        end_col = 11,
        text = { "there" },
        expect = "world",
      },
    })
    eq(result.applied, 1, "stale-match: matching expect applies the edit")
    eq(get_lines(buf)[1], "hello there", "stale-match: text replaced correctly")
  end

  do
    local buf = new_buf({ "hello world" })
    local result = apply_edits(buf, {
      {
        start_row = 0,
        start_col = 6,
        end_row = 0,
        end_col = 11,
        text = { "there" },
        expect = "WRONG",
      },
    })
    eq(result.applied, 0, "stale-match: mismatched expect skips the edit")
    eq(#result.skipped, 1, "stale-match: reports exactly one skip")
    eq(result.skipped[1].reason, "stale-match", "stale-match: skip reason is 'stale-match'")
    eq(result.skipped[1].index, 1, "stale-match: skip references the edit's original index")
    eq(get_lines(buf)[1], "hello world", "stale-match: buffer is untouched when the check fails")
  end

  -- A mix: one edit's expect is stale, another's is fine -- the good one
  -- must still apply.
  do
    local buf = new_buf({ "aaa bbb" })
    local result = apply_edits(buf, {
      { start_row = 0, start_col = 0, end_row = 0, end_col = 3, text = { "AAA" }, expect = "aaa" },
      {
        start_row = 0,
        start_col = 4,
        end_row = 0,
        end_col = 7,
        text = { "BBB" },
        expect = "WRONG",
      },
    })
    eq(result.applied, 1, "mixed: one good edit applies")
    eq(#result.skipped, 1, "mixed: one stale edit is skipped")
    eq(
      result.skipped[1].index,
      2,
      "mixed: the skipped edit's original index (2nd in the array) is preserved"
    )
    eq(get_lines(buf)[1], "AAA bbb", "mixed: only the valid edit's change landed")
  end

  -- ----------------------------------------------------------- text as string

  do
    local buf = new_buf({ "one line" })
    local result = apply_edits(buf, {
      { start_row = 0, start_col = 0, end_row = 0, end_col = 3, text = "1\n2" },
    })
    eq(result.applied, 1, "text-as-string: applied")
    eq(
      joined(get_lines(buf)),
      "1,2 line",
      "text-as-string: split on \\n into multiple buffer lines"
    )
  end

  -- --------------------------------------------------------- out-of-range

  do
    local buf = new_buf({ "short" })
    local result = apply_edits(buf, {
      { start_row = 5, start_col = 0, end_row = 5, end_col = 1, text = { "x" }, expect = "y" },
    })
    eq(result.applied, 0, "out-of-range: an edit past the buffer's end is not applied")
    eq(result.skipped[1].reason, "out-of-range", "out-of-range: skip reason names it")
  end

  ok(true, "apply_edits spec completed")
end
