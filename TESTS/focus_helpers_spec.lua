-- TESTS/focus_helpers_spec.lua — lib.nvim.window.focus_helpers: is_at_bottom,
-- ensure_bottom (both retry mechanisms), make_focusable, force_focus,
-- reveal_at_bottom (degenerate-window skip, normal! G, cursor placement).

return function(H)
  local eq, ok = H.eq, H.ok
  local focus = require("lib.nvim.window.focus_helpers")

  local function scratch_win(lines)
    vim.cmd("vsplit")
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or { "one", "two", "three" })
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
    return win, buf
  end

  -- is_at_bottom
  do
    local win = scratch_win()
    eq(focus.is_at_bottom(win), false, "cursor on line 1 of 3 is not at bottom")
    vim.api.nvim_win_set_cursor(win, { 3, 0 })
    eq(focus.is_at_bottom(win), true, "cursor on the last line is at bottom")
    eq(focus.is_at_bottom(999999), true, "an invalid window counts as at bottom")
    vim.cmd("only")
  end

  -- ensure_bottom: moves the cursor, default opts.
  do
    local win = scratch_win()
    focus.ensure_bottom(win)
    eq(vim.api.nvim_win_get_cursor(win)[1], 3, "ensure_bottom moves the cursor to the last line")
    vim.cmd("only")
  end

  -- ensure_bottom: retries on the next tick while the window doesn't exist yet.
  do
    local win, buf = scratch_win()
    vim.api.nvim_win_close(win, true)
    local fake_winid = win -- closed; nvim_win_is_valid is now false
    ok(
      pcall(focus.ensure_bottom, fake_winid, { retries = 1 }),
      "ensure_bottom on an invalid window does not raise, just defers/gives up"
    )
    vim.wait(50, function()
      return false
    end)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  -- ensure_bottom: attempts > 1 retries if the cursor-set didn't land at
  -- the bottom (e.g. a transient failure right when it's called) -- NOT a
  -- general "poll for new content" loop: the function always forces the
  -- cursor to the buffer's CURRENT last line first, so is_at_bottom() is
  -- trivially true right after a successful set. Simulate the transient
  -- failure directly by intercepting nvim_win_set_cursor for the first
  -- (synchronous) attempt only; the deferred retry runs after the patch is
  -- restored, so it uses the real API and should succeed.
  do
    local win = scratch_win({ "a", "b", "c" })
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
    H.with_patched(vim.api, "nvim_win_set_cursor", function() end, function()
      focus.ensure_bottom(win, { attempts = 2, retry_delay_ms = 20 })
    end)
    eq(
      vim.api.nvim_win_get_cursor(win)[1],
      1,
      "first attempt's cursor-set was intercepted, cursor unchanged"
    )
    vim.wait(200, function()
      return vim.api.nvim_win_get_cursor(win)[1] == 3
    end, 10)
    eq(
      vim.api.nvim_win_get_cursor(win)[1],
      3,
      "the retry (now unpatched) succeeds and reaches the last line"
    )
    vim.cmd("only")
  end

  -- make_focusable
  do
    local floating = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
      relative = "editor",
      row = 0,
      col = 0,
      width = 10,
      height = 3,
      focusable = false,
    })
    eq(focus.make_focusable(floating), true, "make_focusable reports success on a float")
    eq(vim.api.nvim_win_get_config(floating).focusable, true, "the float is now actually focusable")
    eq(
      focus.make_focusable(floating),
      true,
      "calling it again (already focusable) is a harmless no-op success"
    )
    vim.api.nvim_win_close(floating, true)

    local win = scratch_win()
    eq(
      focus.make_focusable(win),
      false,
      "a non-floating window has no 'focusable' concept -- reports false"
    )
    vim.cmd("only")

    eq(focus.make_focusable(999999), false, "an invalid window reports failure")
  end

  -- force_focus
  do
    local win = scratch_win()
    vim.cmd("vsplit")
    ok(vim.api.nvim_get_current_win() ~= win, "sanity: a different window is now current")

    eq(focus.force_focus(win), true, "force_focus switches to a valid (non-floating) window")
    eq(vim.api.nvim_get_current_win(), win, "the window is now current")
    eq(focus.force_focus(999999), false, "an invalid window reports failure")
    vim.cmd("only")
  end

  -- reveal_at_bottom: degenerate windows are skipped.
  do
    local tiny = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
      relative = "editor",
      row = 0,
      col = 0,
      width = 1,
      height = 1,
    })
    eq(focus.reveal_at_bottom(tiny), false, "a 1x1 float is degenerate -- skipped, not revealed")
    vim.api.nvim_win_close(tiny, true)
    eq(focus.reveal_at_bottom(999999), false, "an invalid window is skipped too")
  end

  -- reveal_at_bottom: focuses + scrolls a real window to the bottom.
  do
    local win = scratch_win()
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
    local result = focus.reveal_at_bottom(win, { attempts = 1 })
    eq(result, true, "reveal_at_bottom reports success")
    eq(vim.api.nvim_get_current_win(), win, "focus actually landed on the window")
    eq(vim.api.nvim_win_get_cursor(win)[1], 3, "cursor moved to the last line")
    vim.cmd("only")
  end
end
