-- TESTS/ui_winhighlight_spec.lua — lib.nvim.ui.winhighlight
--
-- Driven against a real window wherever the API touches one: the whole
-- point of the module is that `nvim_set_option_value` accepts what it
-- builds, and a stub cannot show that.

return function(H)
  local eq, ok = H.eq, H.ok

  local wh = require("lib.nvim.ui.winhighlight")

  --- A real, valid window to operate on.
  local function scratch_win()
    local buf = vim.api.nvim_create_buf(false, true)
    return vim.api.nvim_open_win(buf, false, {
      relative = "editor",
      row = 1,
      col = 1,
      width = 10,
      height = 3,
      style = "minimal",
    })
  end

  -- --------------------------------------------------------------- parse
  eq(#wh.parse(nil), 0, "parse(nil) is empty")
  eq(#wh.parse(""), 0, "parse('') is empty")

  local p = wh.parse("Normal:NormalFloat,FloatBorder:FloatBorder")
  eq(#p, 2, "parses two pairs")
  eq(p[1].from, "Normal", "first pair's source")
  eq(p[1].to, "NormalFloat", "first pair's target")

  eq(#wh.parse("  Normal:NormalFloat  "), 1, "surrounding whitespace is trimmed")
  eq(#wh.parse("garbage"), 0, "an entry with no colon is dropped")
  eq(#wh.parse("a:b:c"), 0, "an entry with two colons is dropped")
  eq(#wh.parse("Normal:"), 0, "an entry with an empty target is dropped")
  eq(#wh.parse(":NormalFloat"), 0, "an entry with an empty source is dropped")
  eq(#wh.parse("Normal:NormalFloat,junk"), 1, "a bad entry does not discard the good ones")

  -- The regression this module exists to fix. `my.nvim`'s original
  -- validated `^[%w_]+$`, so every mapping to a Tree-sitter capture was
  -- silently dropped -- and `@`-prefixed groups are not exotic.
  eq(#wh.parse("Normal:@comment"), 1, "a Tree-sitter capture target survives")
  eq(wh.parse("Normal:@comment")[1].to, "@comment", "...with its @ intact")
  eq(#wh.parse("Normal:Foo.Bar"), 1, "a dotted group name survives")
  eq(#wh.parse("Normal:Foo-Bar"), 1, "a hyphenated group name survives")

  -- ----------------------------------------------------------- serialize
  eq(wh.serialize({}), "", "serializing nothing gives an empty string")
  eq(
    wh.serialize({ { from = "Normal", to = "NormalFloat" } }),
    "Normal:NormalFloat",
    "serializes one pair"
  )
  eq(
    wh.serialize({ { from = "Nor,mal", to = "X" } }),
    "",
    "a pair whose name carries a comma is refused on the way out"
  )

  -- --------------------------------------------------------------- merge
  eq(
    wh.merge("", { Normal = "NormalFloat" }),
    "Normal:NormalFloat",
    "merging into an empty value"
  )

  local merged = wh.parse(wh.merge("Normal:A,Cursor:B", { Normal = "C" }))
  eq(#merged, 2, "merge keeps the mapping it did not touch")
  local by_from = {}
  for _, e in ipairs(merged) do
    by_from[e.from] = e.to
  end
  eq(by_from.Normal, "C", "a new mapping overrides the old one for the same source")
  eq(by_from.Cursor, "B", "an unrelated mapping is preserved")

  -- ------------------------------------------------------------ set_pair
  eq(wh.set_pair("Normal:A", "Cursor", "B"), "Normal:A,Cursor:B", "set_pair appends")
  eq(wh.set_pair("Normal:A,Cursor:B", "Cursor", nil), "Normal:A", "set_pair(nil) removes")
  eq(wh.set_pair("Normal:A", "Nope", nil), "Normal:A", "removing what is not there is a no-op")

  -- ------------------------------------------------- against a real window
  --
  -- Asserted per mapping rather than on the whole string: a new window
  -- inherits whatever global `winhighlight` is in effect, and in this
  -- shared runner an earlier spec has usually set one. Which is the
  -- module's own subject -- so the test is written the way callers should
  -- think, in terms of their own pairs and nobody else's.
  do
    local win = scratch_win()

    --- The target `from` currently maps to on `win`, or nil.
    ---@return string|nil
    local function target(from)
      for _, e in ipairs(wh.parse(wh.get(win))) do
        if e.from == from then
          return e.to
        end
      end
      return nil
    end

    local inherited = #wh.parse(wh.get(win))

    ok(wh.update(win, { LibSpecWhA = "NormalFloat" }), "update() succeeds on a live window")
    eq(target("LibSpecWhA"), "NormalFloat", "...and the window carries the mapping")

    -- The behaviour the direct-assignment call sites got wrong.
    ok(wh.update(win, { LibSpecWhB = "FloatBorder" }), "a second update() succeeds")
    eq(target("LibSpecWhA"), "NormalFloat", "the second update did not discard the first")
    eq(target("LibSpecWhB"), "FloatBorder", "...and added its own")

    ok(wh.remove(win, "LibSpecWhA"), "remove() succeeds")
    eq(target("LibSpecWhA"), nil, "remove() drops the named mapping")
    eq(target("LibSpecWhB"), "FloatBorder", "...and only that one")

    ok(wh.update(win, { LibSpecWhC = "@comment" }), "a Tree-sitter target is accepted by nvim")
    eq(target("LibSpecWhC"), "@comment", "...and survives the round trip through the option")

    ok(wh.remove(win, { "LibSpecWhB", "LibSpecWhC" }), "remove() takes a list")
    eq(target("LibSpecWhB"), nil, "both named mappings are gone")
    eq(target("LibSpecWhC"), nil, "both named mappings are gone")
    eq(
      #wh.parse(wh.get(win)),
      inherited,
      "whatever the window inherited is still there, untouched throughout"
    )

    vim.api.nvim_win_close(win, true)
  end

  -- ------------------------------------------------------- invalid window
  do
    local win = scratch_win()
    vim.api.nvim_win_close(win, true)

    eq(wh.get(win), "", "get() on a closed window is empty, not an error")
    eq(wh.apply(win, "Normal:A"), false, "apply() on a closed window reports failure")
    eq(wh.update(win, { Normal = "A" }), false, "update() on a closed window reports failure")
    eq(wh.remove(win, "Normal"), false, "remove() on a closed window reports failure")
  end
end
