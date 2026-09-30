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
end
