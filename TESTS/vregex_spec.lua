-- TESTS/vregex_spec.lua — lib.nvim.vregex

return function(H)
  local eq, ok = H.eq, H.ok

  local vregex = require("lib.nvim.vregex")

  -- ----------------------------------------------------------------- escape

  eq(vregex.escape("plain"), "plain", "escape: text with no backslash is unchanged")
  eq(vregex.escape("a\\b"), "a\\\\b", "escape: a single backslash is doubled")
  eq(
    vregex.escape("a.b*c[d]"),
    "a.b*c[d]",
    "escape: metacharacters are left alone (that's \\V's job)"
  )

  -- ---------------------------------------------------------------- literal

  eq(
    vregex.literal("a.b*c"),
    "\\Va.b*c",
    "literal: prefixes \\V, leaves metacharacters as literal text under it"
  )
  eq(
    vregex.literal("a\\b"),
    "\\Va\\\\b",
    "literal: backslash in the input is escaped before the \\V prefix"
  )

  eq(
    vregex.literal("word", { whole_word = true }),
    "\\V\\<word\\>",
    "literal: whole_word wraps with \\< \\> word-boundary atoms"
  )

  eq(vregex.literal("Foo", { case = "ignore" }), "\\c\\VFoo", "literal: case=ignore prefixes \\c")
  eq(vregex.literal("Foo", { case = "match" }), "\\C\\VFoo", "literal: case=match prefixes \\C")

  eq(
    vregex.literal("id", { whole_word = true, case = "ignore" }),
    "\\c\\V\\<id\\>",
    "literal: whole_word and case combine"
  )

  -- ------------------------------------------------------ actual vim regex

  -- The whole point: text containing regex metacharacters must match itself
  -- literally, nowhere else, when fed to a real Vim search.
  do
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "a.b*c matches here",
      "aXbYYc should not match",
      "prefix a.b*c suffix",
    })
    local win = vim.api.nvim_open_win(buf, false, {
      relative = "editor",
      row = 0,
      col = 0,
      width = 10,
      height = 3,
    })
    vim.api.nvim_win_set_cursor(win, { 1, 0 })

    local pattern = vregex.literal("a.b*c")
    local count = 0
    vim.api.nvim_win_call(win, function()
      vim.fn.cursor(1, 1)
      local first = true
      while true do
        -- 'c': allow the very first match to land exactly at the cursor
        -- (line 1's match starts at col 1, right where the cursor begins).
        -- Every subsequent search omits 'c' so it doesn't rematch the same spot.
        local line = vim.fn.search(pattern, first and "cW" or "W")
        first = false
        if line == 0 then
          break
        end
        count = count + 1
      end
    end)
    eq(
      count,
      2,
      "literal: a real vim.fn.search only matches the literal text, twice, not the fake lookalike"
    )

    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, { force = true })
  end

  -- whole_word: must not match as a substring of a longer identifier.
  do
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "grid idea id",
      "id",
    })
    local win = vim.api.nvim_open_win(buf, false, {
      relative = "editor",
      row = 0,
      col = 0,
      width = 20,
      height = 2,
    })

    local pattern = vregex.literal("id", { whole_word = true })
    local count = 0
    vim.api.nvim_win_call(win, function()
      vim.fn.cursor(1, 1)
      while true do
        local line = vim.fn.search(pattern, "W")
        if line == 0 then
          break
        end
        count = count + 1
      end
    end)
    -- "grid" and "idea" both contain "id" as a substring; only the two
    -- standalone occurrences should count under whole_word.
    eq(count, 2, "literal: whole_word only matches the standalone word, not 'id' inside grid/idea")

    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, { force = true })
  end

  ok(true, "vregex spec completed")
end
