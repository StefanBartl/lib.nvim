-- TESTS/window_matches_spec.lua — lib.nvim.window.matches: a named, per-window ledger over matchadd/matchdelete.

return function(H)
  local eq, ok = H.eq, H.ok
  local matches = require("lib.nvim.window.matches")

  vim.cmd("silent! only")
  local w1 = vim.api.nvim_get_current_win()
  vim.cmd("vsplit")
  local w2 = vim.api.nvim_get_current_win()

  ---@param win integer
  ---@return integer
  local function real_count(win)
    return #vim.fn.getmatches(win)
  end

  local ledger = matches.new()

  -- add: a real match, in that window only
  local id, err = ledger:add(w1, "word", "Search", "foo", { priority = 7 })
  ok(type(id) == "number" and err == nil, "add: returns the match id")
  eq(real_count(w1), 1, "add: the match exists in the window")
  eq(real_count(w2), 0, "add: ... and not in the other window")
  eq(vim.fn.getmatches(w1)[1].priority, 7, "add: the priority is passed on")
  ok(ledger:has(w1, "word"), "has: true for a ledger match")
  eq(ledger:has(w2, "word"), false, "has: per window")

  -- same name replaces; a different name coexists
  local id2 = ledger:add(w1, "word", "Search", "bar")
  eq(real_count(w1), 1, "add: the same name replaces the earlier match")
  ok(id2 ~= id, "add: ... with a new match id")
  ledger:add(w1, "other", "Search", "baz")
  ledger:add(w2, "word", "Search", "qux")
  eq(real_count(w1), 2, "add: another name coexists")
  eq(real_count(w2), 1, "add: the other window has its own")

  -- a bad pattern keeps the previous highlight and reports why
  local bad_id, bad_err = ledger:add(w1, "word", "Search", "\\(")
  eq(bad_id, nil, "add: a bad pattern is refused")
  ok(type(bad_err) == "string" and bad_err ~= "", "add: ... with a reason")
  ok(ledger:has(w1, "word"), "add: ... and the previous match under that name is kept")

  -- list
  local listed = ledger:list(w1)
  ok(listed.word ~= nil and listed.other ~= nil, "list: name -> id for both")
  eq(vim.tbl_count(ledger:list(w2)), 1, "list: per window")

  -- add_pos
  local pid = ledger:add_pos(w2, "line", "Search", { { 1, 1, 1 } })
  ok(type(pid) == "number", "add_pos: returns the match id")
  eq(real_count(w2), 2, "add_pos: the match exists")

  -- remove
  eq(ledger:remove(w1, "other"), true, "remove: an existing match")
  eq(real_count(w1), 1, "remove: it is gone from the window")
  eq(ledger:remove(w1, "other"), false, "remove: a second time reports false")
  eq(ledger:remove(w1, ""), false, "remove: an empty name is false")

  -- a match removed behind the ledger's back counts as gone
  local before = ledger:list(w2).word
  vim.fn.matchdelete(before, w2)
  eq(ledger:has(w2, "word"), false, "has: a match deleted elsewhere is gone")
  eq(ledger:list(w2).word, nil, "list: ... and not listed")
  eq(ledger:remove(w2, "word"), false, "remove: ... and nothing to remove")

  -- clear
  ledger:add(w1, "again", "Search", "zzz")
  eq(ledger:clear(w1), 2, "clear: returns how many it removed")
  eq(real_count(w1), 0, "clear: the window has none left")
  eq(ledger:clear(w1), 0, "clear: nothing left to clear")
  ok(real_count(w2) >= 1, "clear: other windows are untouched")

  -- somebody else's matches in the same window are left alone
  vim.fn.matchadd("Search", "foreign", 10, -1, { window = w1 })
  ledger:add(w1, "mine", "Search", "mine")
  ledger:clear_all()
  eq(real_count(w1), 1, "clear_all: only the ledger's matches go, a foreign one stays")
  eq(real_count(w2), 0, "clear_all: every window")
  vim.fn.clearmatches(w1)

  -- two ledgers are independent
  local a, b = matches.new(), matches.new()
  a:add(w1, "n", "Search", "a")
  b:add(w1, "n", "Search", "b")
  eq(real_count(w1), 2, "two ledgers: each holds its own match under the same name")
  a:clear_all()
  eq(real_count(w1), 1, "two ledgers: clearing one leaves the other")
  b:clear_all()

  -- a closed window is forgotten, not an error
  vim.cmd("vsplit")
  local w3 = vim.api.nvim_get_current_win()
  ledger:add(w3, "x", "Search", "x")
  vim.api.nvim_win_close(w3, true)
  eq(vim.tbl_count(ledger:list(w3)), 0, "closed window: nothing listed")
  eq(ledger:has(w3, "x"), false, "closed window: has is false")
  eq(ledger:remove(w3, "x"), false, "closed window: remove is false, not an error")

  -- invalid input
  local e_id, e_err = ledger:add(99999, "x", "Search", "x")
  ok(e_id == nil and e_err == "invalid window", "add: an invalid window is refused")
  e_id, e_err = ledger:add(w1, "", "Search", "x")
  ok(e_id == nil and type(e_err) == "string", "add: an empty name is refused")
  e_id = ledger:add_pos(99999, "x", "Search", { { 1 } })
  eq(e_id, nil, "add_pos: an invalid window is refused")

  vim.cmd("silent! only")
end
