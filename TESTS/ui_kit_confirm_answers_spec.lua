-- Test code: when something here comes back nil, this file must crash and
-- name it rather than silently skip -- see TESTS/ui_kit_spec.lua's header.
---@diagnostic disable: need-check-nil
-- TESTS/ui_kit_confirm_answers_spec.lua -- lib.nvim.ui.kit.confirm answers exactly once, whichever
-- way its float goes away: confirmed, cancelled, closed from outside (`nvim_win_close`, `:only`),
-- replaced by a second dialog, or `confirm.close()`. Port of ui.nvim's spec of the same name.

return function(_)
  local kit = require("lib.nvim.ui.kit")
  local confirm = require("lib.nvim.ui.kit.confirm")
  local api = vim.api

  local function close_all()
    confirm.close()
    for _, w in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_is_valid(w) and api.nvim_win_get_config(w).relative ~= "" then
        pcall(api.nvim_win_close, w, true)
      end
    end
  end

  ---@param opts? table
  ---@return table calls, Lib.UI.Kit.Surface surf
  local function open(opts)
    local calls = {}
    local o = vim.tbl_extend("force", { question = "Q?" }, opts or {})
    o.on_answer = function(v)
      calls[#calls + 1] = v == nil and "nil" or v
    end
    local surf = kit.confirm(o)
    assert(surf, "the dialog opened")
    return calls, surf
  end

  local function eq(actual, expected, msg)
    assert(
      vim.deep_equal(actual, expected),
      ("%s: expected %s, got %s"):format(msg, vim.inspect(expected), vim.inspect(actual))
    )
  end

  -- confirmed / cancelled keep working, once each
  local calls = open()
  confirm.confirm()
  eq(calls, { true }, "confirm -> true, once")
  calls = open()
  confirm.cancel()
  eq(calls, { false }, "cancel -> false, once")
  calls = open({ choices = { "a", "b" } })
  confirm.cancel()
  eq(calls, { "nil" }, "cancel with choices -> nil, once")

  -- closed from outside: the float vanishes without confirm/cancel. The answer is scheduled
  -- (the hook runs inside WinClosed under pcall, where an error in on_answer would vanish).
  local function answered(c, n)
    vim.wait(500, function()
      return #c >= n
    end, 5)
  end
  local surf
  calls, surf = open()
  api.nvim_win_close(surf.winid, true)
  eq(confirm.is_open(), false, "and the dialog is no longer open")
  answered(calls, 1)
  eq(calls, { false }, "float closed from outside -> false, once")

  calls, surf = open({ choices = { "a", "b" } })
  api.nvim_win_close(surf.winid, true)
  answered(calls, 1)
  eq(calls, { "nil" }, "float closed from outside with choices -> nil, once")

  -- a dialog opened right after an external close is not answered by the late answer
  local late, late_surf = open({ question = "late" })
  api.nvim_win_close(late_surf.winid, true)
  local next_calls = open({ question = "next" })
  answered(late, 1)
  eq(late, { false }, "the externally closed dialog is answered once")
  eq(next_calls, {}, "the dialog opened right after it is untouched")
  confirm.confirm()
  eq(next_calls, { true }, "and answers on its own")

  -- an ask-owned dialog closed from outside answers the question with "no", once
  local asked = {}
  kit.ask({
    question = "asked?",
    on_answer = function(v)
      asked[#asked + 1] = v
    end,
  })
  assert(confirm.is_open(), "the ask is showing")
  -- the dialog's float is entered, so it is the current window
  api.nvim_win_close(api.nvim_get_current_win(), true)
  answered(asked, 1)
  eq(asked, { false }, "ask: float closed from outside -> false, once")

  -- replaced by a second dialog: the first one is answered as cancelled
  local first = open()
  local second = open({ question = "second" })
  eq(first, { false }, "a replaced dialog is answered as cancelled")
  eq(second, {}, "and the new one is still waiting")
  confirm.confirm()
  eq(second, { true }, "the new one answers on its own")
  eq(first, { false }, "the replaced one does not answer twice")

  -- a replaced dialog whose answer opens a dialog itself: that one replaces the replacement
  -- (last one wins, every dialog is answered once) and is not left orphaned on screen
  local reopened = {}
  local from_cb = {}
  kit.confirm({
    question = "old",
    on_answer = function(v)
      from_cb[#from_cb + 1] = v
      reopened = open({ question = "opened from the answer" })
    end,
  })
  local replacement = open({ question = "replacement" })
  eq(from_cb, { false }, "the replaced dialog was answered once")
  eq(replacement, { false }, "the replacement was replaced in turn and answered once")
  eq(reopened, {}, "the dialog opened from the answer is still waiting")
  eq(confirm.is_open(), true, "and open: its float is not orphaned")
  confirm.confirm()
  eq(reopened, { true }, "it answers on its own")
  eq(confirm.is_open(), false, "and no float is left behind")

  -- confirm.close() ends the dialog and answers as cancelled
  calls = open()
  confirm.close()
  eq(calls, { false }, "close() -> false, once")
  confirm.close()
  eq(calls, { false }, "close() on a closed dialog is a no-op")

  -- confirming from inside a callback that opens the next dialog does not answer the next one
  local outer = {}
  local inner
  kit.confirm({
    question = "outer",
    on_answer = function(v)
      outer[#outer + 1] = v
      inner = open({ question = "inner" })
    end,
  })
  confirm.confirm()
  eq(outer, { true }, "the outer dialog answered once")
  eq(inner, {}, "the dialog opened in the callback is untouched")
  close_all()
end
