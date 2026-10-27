-- Test code: when something here comes back nil, this file must crash and
-- name it rather than silently skip -- see TESTS/ui_kit_spec.lua's header.
---@diagnostic disable: need-check-nil
-- TESTS/ui_kit_confirm_answers_spec.lua -- lib.nvim.ui.kit.confirm answers exactly once, whichever
-- way its float goes away: confirmed, cancelled, closed from outside (`nvim_win_close`, `:only`),
-- replaced by a second dialog, or `confirm.close()`. Port of ui.nvim's spec of the same name.

return function(H)
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
    H.ok(surf ~= nil, "the dialog opened")
    return calls, surf
  end

  local function same(actual, expected, msg)
    H.ok(
      vim.deep_equal(actual, expected),
      ("%s: expected %s, got %s"):format(msg, vim.inspect(expected), vim.inspect(actual))
    )
  end

  -- confirmed / cancelled keep working, once each
  local calls = open()
  confirm.confirm()
  same(calls, { true }, "confirm -> true, once")
  calls = open()
  confirm.cancel()
  same(calls, { false }, "cancel -> false, once")
  calls = open({ choices = { "a", "b" } })
  confirm.cancel()
  same(calls, { "nil" }, "cancel with choices -> nil, once")

  -- closed from outside: the float vanishes without confirm/cancel
  local surf
  calls, surf = open()
  api.nvim_win_close(surf.winid, true)
  same(calls, { false }, "float closed from outside -> false, once")
  H.eq(confirm.is_open(), false, "and the dialog is no longer open")

  calls, surf = open({ choices = { "a", "b" } })
  api.nvim_win_close(surf.winid, true)
  same(calls, { "nil" }, "float closed from outside with choices -> nil, once")

  -- replaced by a second dialog: the first one is answered as cancelled
  local first = open()
  local second = open({ question = "second" })
  same(first, { false }, "a replaced dialog is answered as cancelled")
  same(second, {}, "and the new one is still waiting")
  confirm.confirm()
  same(second, { true }, "the new one answers on its own")
  same(first, { false }, "the replaced one does not answer twice")

  -- confirm.close() ends the dialog and answers as cancelled
  calls = open()
  confirm.close()
  same(calls, { false }, "close() -> false, once")
  confirm.close()
  same(calls, { false }, "close() on a closed dialog is a no-op")

  -- a dialog opened from inside the callback is not answered by the outer one
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
  same(outer, { true }, "the outer dialog answered once")
  same(inner, {}, "the dialog opened in the callback is untouched")
  close_all()
end
