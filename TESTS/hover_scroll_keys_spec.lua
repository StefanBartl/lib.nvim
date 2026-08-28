-- TESTS/hover_scroll_keys_spec.lua — which keys scroll a hover preview, and
-- what happens to the keys they borrow.
--
-- The scroll keys are bound *globally* while a scrollable float is on screen,
-- because the float is `focusable = false` and can never hold a mapping of
-- its own. That makes two things worth asserting and easy to get wrong: the
-- configured list must replace the default rather than merge into it (a
-- `tbl_deep_extend` list merge would silently keep the default key alive),
-- and a key that was already mapped must come back afterwards rather than be
-- deleted with the hover.
--
-- The default list carries a second, Fn-free pair (`<C-Down>`/`<C-Up>`)
-- because PageUp/PageDown do not exist on every keyboard and nothing at
-- runtime can ask.

---@param H table harness from TESTS/run.lua
return function(H)
  local eq, ok = H.eq, H.ok

  local hover = require("lib.nvim.hover")

  --- `H.eq` compares by identity, and every assertion here is about a list.
  ---@param a any
  ---@param b any
  ---@param msg string
  local function same(a, b, msg)
    ok(vim.deep_equal(a, b), msg .. " (got " .. vim.inspect(a) .. ")")
  end

  ---@return string|nil desc of the normal-mode mapping for `lhs`, if any
  local function mapped(lhs)
    local m = vim.fn.maparg(lhs, "n", false, true)
    return type(m) == "table" and m.desc or nil
  end

  -- ── Configuration ───────────────────────────────────────────────────────
  local c = hover.setup()
  same(c.scroll_keys.down, { "<M-PageDown>", "<C-Down>" }, "both forward keys are on by default")
  same(c.scroll_keys.up, { "<M-PageUp>", "<C-Up>" }, "…and both back keys")

  c = hover.setup({ scroll_keys = { down = { "<C-n>" } } })
  same(
    c.scroll_keys.down,
    { "<C-n>" },
    "a configured list replaces the default, index-merging none of it"
  )
  same(c.scroll_keys.up, { "<M-PageUp>", "<C-Up>" }, "…and leaves the other direction alone")

  c = hover.setup({ scroll_keys = { up = "<C-p>" }, max_lines = 3 })
  eq(c.scroll_keys.up, "<C-p>", "a bare string is accepted as one key")
  same(c.scroll_keys.down, { "<C-n>" }, "a second setup() does not reset the first")

  -- ── Binding, scrolling, unbinding ───────────────────────────────────────
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")
  local long = tmp .. "/long.txt"
  local lines = {}
  for i = 1, 200 do
    lines[i] = "line " .. i
  end
  vim.fn.writefile(lines, long)
  local doc = tmp .. "/doc.md"
  vim.fn.writefile({ "see ./long.txt here" }, doc)

  hover.setup({
    scroll_keys = { down = { "<M-PageDown>", "<C-Down>" }, up = { "<M-PageUp>", "<C-Up>" } },
    max_lines = 3,
  })

  -- A key of the user's that one of the defaults is about to shadow.
  vim.keymap.set("n", "<C-Down>", "<Cmd>echo 'mine'<CR>", { desc = "user mapping" })

  vim.cmd.edit(doc)
  vim.api.nvim_win_set_cursor(0, { 1, 6 })
  ok(hover.show({ force = true }), "a bare path in the line opens a hover")
  vim.wait(500, function()
    return mapped("<M-PageDown>") ~= nil
  end)

  ok(
    (mapped("<M-PageDown>") or ""):find("scroll preview down", 1, true) ~= nil,
    "the PageDown key is bound"
  )
  ok(
    (mapped("<C-Down>") or ""):find("scroll preview down", 1, true) ~= nil,
    "…and so is the Fn-free alternative"
  )
  ok(
    (mapped("<M-PageUp>") or ""):find("scroll preview up", 1, true) ~= nil,
    "the back key is bound too"
  )

  ok(hover.scroll(1), "scrolling forward re-renders the preview")
  vim.wait(500)

  hover.hide()
  eq(mapped("<M-PageDown>"), nil, "closing the hover takes its own key away")
  eq(mapped("<C-Down>"), "user mapping", "…and hands back the mapping it had borrowed")

  pcall(vim.keymap.del, "n", "<C-Down>")
  vim.fn.delete(tmp, "rf")
  vim.cmd("silent! %bwipeout!")

  -- Leave the module as the next spec would expect to find it.
  hover.setup({
    scroll_keys = { down = { "<M-PageDown>", "<C-Down>" }, up = { "<M-PageUp>", "<C-Up>" } },
    max_lines = 20,
  })
end
