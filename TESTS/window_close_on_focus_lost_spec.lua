-- TESTS/window_close_on_focus_lost_spec.lua -- lib.nvim.window.close_on_focus_lost: the default closes the
-- window once focus leaves it; `recheck` ignores focus that came back at once and stays armed; `close`
-- replaces the plain window close.

return function(H)
  local eq = H.eq
  local close_on_focus_lost = require("lib.nvim.window.close_on_focus_lost")
  local api = vim.api

  local function float()
    local buf = api.nvim_create_buf(false, true)
    local win = api.nvim_open_win(buf, true, {
      relative = "editor",
      row = 1,
      col = 1,
      width = 10,
      height = 2,
      style = "minimal",
    })
    return win, buf
  end

  local function leave_to_other(win)
    vim.cmd("wincmd p")
    eq(api.nvim_get_current_win() ~= win, true, "focus moved to another window")
    vim.wait(100)
  end

  -- default: closed on focus loss
  local origin = api.nvim_get_current_win()
  local win = float()
  close_on_focus_lost(win)
  api.nvim_set_current_win(origin)
  vim.wait(200, function()
    return not api.nvim_win_is_valid(win)
  end, 5)
  eq(api.nvim_win_is_valid(win), false, "default: the window closes when focus leaves it")

  -- recheck + custom close: focus that returns at once is ignored, a real loss runs `close`
  win = float()
  local closed = {}
  close_on_focus_lost(win, {
    events = { "WinLeave" },
    recheck = true,
    close = function(w)
      closed[#closed + 1] = w
      pcall(api.nvim_win_close, w, true)
    end,
  })
  -- a blip: out and straight back, inside one loop turn
  api.nvim_set_current_win(origin)
  api.nvim_set_current_win(win)
  vim.wait(100)
  eq(#closed, 0, "recheck: focus that came back is left alone")
  eq(api.nvim_win_is_valid(win), true, "recheck: the window is still there")
  -- the hook is still armed: a real loss closes it, through `close`
  leave_to_other(win)
  vim.wait(200, function()
    return #closed > 0
  end, 5)
  eq(closed[1], win, "recheck: a real loss runs the caller's close")
  eq(api.nvim_win_is_valid(win), false, "...which closed the window")
end
