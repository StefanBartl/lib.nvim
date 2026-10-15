-- TESTS/window_best_target_spec.lua — lib.nvim.window.find_usable.best_target_window:
-- source_win -> alternate window -> first usable window, each a normal window with a modifiable buffer.

return function(H)
  local eq = H.eq
  local fu = require("lib.nvim.window.find_usable")

  vim.cmd("silent! only")
  local first = vim.api.nvim_get_current_win()
  vim.cmd("vsplit")
  local second = vim.api.nvim_get_current_win()
  vim.cmd("vsplit")
  local third = vim.api.nvim_get_current_win()

  -- 1) an explicit source window wins over the alternate window
  vim.api.nvim_set_current_win(second)
  vim.api.nvim_set_current_win(third) -- alternate is now `second`
  eq(fu.best_target_window({ source_win = first }), first, "source_win wins")

  -- 2) no source window: the alternate window (`:wincmd p`), not the first in list order
  eq(fu.best_target_window(), second, "the alternate window comes next")

  -- 3) an unusable source window falls through
  local buf = vim.api.nvim_create_buf(false, true)
  local float = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = 1,
    col = 1,
    width = 10,
    height = 2,
  })
  eq(fu.best_target_window({ source_win = float }), second, "a floating source_win is skipped")
  eq(fu.best_target_window({ source_win = 99999 }), second, "an invalid source_win is skipped")
  eq(fu.best_target_window({ source_win = "x" }), second, "a non-number source_win is skipped")

  -- 4) the alternate window is a float: the first usable window in the list
  vim.api.nvim_set_current_win(float)
  vim.api.nvim_set_current_win(third)
  vim.api.nvim_set_current_win(float) -- alternate is `third`
  vim.api.nvim_set_current_win(float)
  local got = fu.best_target_window()
  eq(got ~= float, true, "never the float")
  eq(vim.api.nvim_win_is_valid(got), true, "a real window")

  -- 5) a non-writable buffer is skipped by default, accepted with writable = false
  vim.api.nvim_set_current_win(first)
  local ro = vim.api.nvim_create_buf(false, true)
  vim.bo[ro].modifiable = false
  vim.api.nvim_win_set_buf(second, ro)
  eq(
    fu.best_target_window({ source_win = second }) ~= second,
    true,
    "a non-modifiable window is skipped"
  )
  eq(
    fu.best_target_window({ source_win = second, writable = false }),
    second,
    "writable = false accepts it"
  )

  local term_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[term_buf].buftype = "nofile"
  vim.api.nvim_win_set_buf(third, term_buf)
  eq(fu.best_target_window({ source_win = third }) ~= third, true, "a special buftype is skipped")

  -- 6) only unusable windows: nil
  vim.api.nvim_win_set_buf(first, ro)
  eq(fu.best_target_window(), nil, "nothing writable: nil")
  eq(
    fu.best_target_window({ writable = false }) ~= nil,
    true,
    "... but fine when writing is not needed"
  )

  -- 7) current_tab_only limits the last resort
  vim.cmd("tabnew")
  local other = fu.best_target_window({ current_tab_only = true })
  eq(
    vim.api.nvim_win_get_tabpage(other) == vim.api.nvim_get_current_tabpage(),
    true,
    "current_tab_only stays in the tab"
  )
  vim.cmd("tabclose")

  -- the aggregator exports it
  eq(
    require("lib.nvim.window").best_target_window,
    fu.best_target_window,
    "exported on lib.nvim.window"
  )

  vim.api.nvim_win_close(float, true)
  vim.cmd("silent! only")
  vim.cmd("enew")
end
