-- TESTS/window_previous_spec.lua — lib.nvim.window.find_usable.previous_window

return function(H)
  local eq = H.eq
  local fu = require("lib.nvim.window.find_usable")

  vim.cmd("only")
  local first = vim.api.nvim_get_current_win()
  vim.cmd("vsplit")
  local second = vim.api.nvim_get_current_win()
  vim.cmd("vsplit")
  local third = vim.api.nvim_get_current_win()

  -- Came from `first` into `third`: the previous window is `first`, not the
  -- first-in-list window `target_window()` would hand out.
  vim.api.nvim_set_current_win(first)
  vim.api.nvim_set_current_win(third)
  eq(fu.previous_window(), first, "the window we came from wins")

  -- A float is never usable, even when it was the previous window.
  local fbuf = vim.api.nvim_create_buf(false, true)
  local float = vim.api.nvim_open_win(
    fbuf,
    true,
    { relative = "editor", row = 0, col = 0, width = 5, height = 1 }
  )
  vim.api.nvim_set_current_win(second)
  eq(fu.previous_window() ~= float, true, "a floating previous window is skipped")
  pcall(vim.api.nvim_win_close, float, true)

  vim.cmd("only")
  eq(
    fu.previous_window(),
    vim.api.nvim_get_current_win(),
    "single window: falls back to target_window()"
  )

  -- insertion_window: the current window when it is a normal editing window (a command
  -- typed in the editor), else the previous one (an action from a sidebar/float).
  vim.cmd("only")
  local a = vim.api.nvim_get_current_win()
  vim.cmd("vsplit")
  local b = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(a)
  vim.api.nvim_set_current_win(b)
  eq(
    fu.insertion_window(),
    b,
    "typed in the editor: the current window, not the one visited before"
  )
  local fb = vim.api.nvim_create_buf(false, true)
  local fw = vim.api.nvim_open_win(
    fb,
    true,
    { relative = "editor", row = 0, col = 0, width = 5, height = 1 }
  )
  eq(fu.insertion_window() ~= fw, true, "from a float: never the float")
  pcall(vim.api.nvim_win_close, fw, true)
  vim.cmd("only")
end
