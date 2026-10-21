-- Test code: when something here comes back nil, this file must crash and
-- name it rather than silently skip -- see TESTS/ui_kit_spec.lua's header.
---@diagnostic disable: need-check-nil
-- TESTS/ui_kit_ask_spec.lua -- lib.nvim.ui.kit.confirm.ask: the yes/no question that waits its
-- turn (kit.confirm is single-instance and drops an open dialog UNANSWERED), answers "no" when it
-- gets no answer, and falls back to vim.ui.select when the float cannot open.

return function(H)
  local eq, ok = H.eq, H.ok
  local kit = require("lib.nvim.ui.kit")
  local confirm = require("lib.nvim.ui.kit.confirm")
  local api = vim.api

  vim.o.showmode = false
  confirm.ASK_POLL_MS = 10

  local function close_all()
    confirm.close()
    for _, w in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_is_valid(w) and api.nvim_win_get_config(w).relative ~= "" then
        pcall(api.nvim_win_close, w, true)
      end
    end
  end

  -- ---------------------------------------------------------------- idle: shows at once
  local a
  kit.ask({
    question = "first?",
    on_answer = function(yes)
      a = yes
    end,
  })
  ok(confirm.is_open(), "ask with no dialog open shows its own at once")
  confirm.confirm() -- Yes
  eq(a, true, "ask: Yes -> true")

  kit.ask({
    question = "again?",
    on_answer = function(yes)
      a = yes
    end,
  })
  confirm.cancel()
  eq(a, false, "ask: cancel -> false")

  -- ---------------------------------------------------------------- waits for an open dialog
  local first, second
  confirm.open({
    question = "open one",
    on_answer = function(yes)
      first = yes
    end,
  })
  kit.ask({
    question = "waiting",
    on_answer = function(yes)
      second = yes
    end,
  })
  eq(second, nil, "ask does not answer while another dialog is open")
  eq(first, nil, "ask does not close the open dialog unanswered")
  confirm.confirm() -- answer the first: Yes
  eq(first, true, "the open dialog still gets its own answer")
  ok(
    vim.wait(500, function()
      return confirm.is_open()
    end, 5),
    "the waiting question opens once the first is answered"
  )
  confirm.confirm()
  eq(second, true, "the waiting question gets its own answer")

  -- ---------------------------------------------------------------- gives up: answered "no"
  local timed_out
  confirm.open({ question = "never answered", on_answer = function() end })
  kit.ask({
    question = "starved",
    max_wait_ms = 40,
    on_answer = function(yes)
      timed_out = yes
    end,
  })
  ok(
    vim.wait(1000, function()
      return timed_out ~= nil
    end, 5),
    "a question starved past max_wait_ms is answered"
  )
  eq(timed_out, false, "a starved question is answered as declined")
  close_all()

  -- ---------------------------------------------------------------- abandoned: never asked
  local ab_called = false
  confirm.open({ question = "blocker", on_answer = function() end })
  kit.ask({
    question = "dropped",
    abandoned = function()
      return true
    end,
    on_answer = function()
      ab_called = true
    end,
  })
  vim.wait(80, function()
    return false
  end, 5)
  close_all()
  vim.wait(80, function()
    return false
  end, 5)
  eq(ab_called, false, "an abandoned question is dropped unasked")

  -- ---------------------------------------------------------------- float fails: vim.ui.select
  local orig_open, orig_select = confirm.open, vim.ui.select
  local picked_prompt
  confirm.open = function(o)
    o.on_answer(false) -- what the real open does when the float cannot be created
    return nil
  end
  vim.ui.select = function(items, o, cb)
    picked_prompt = o.prompt
    eq(table.concat(items, "|"), "Yes|No", "the fallback offers Yes/No")
    cb("Yes")
  end
  local fb
  kit.ask({
    question = "fallback?",
    on_answer = function(yes)
      fb = yes
    end,
  })
  confirm.open, vim.ui.select = orig_open, orig_select
  eq(picked_prompt, "fallback?", "the fallback carries the question")
  eq(fb, true, "the fallback's Yes is the answer, not the failed float's synchronous no")

  -- a dialog that opens and answers at once (a stub, another implementation) is a real answer
  confirm.open = function(o)
    o.on_answer(false)
    return {}
  end
  vim.ui.select = function()
    error("the fallback must not run when the dialog opened")
  end
  local instant
  kit.ask({
    question = "instant?",
    on_answer = function(yes)
      instant = yes
    end,
  })
  confirm.open, vim.ui.select = orig_open, orig_select
  eq(instant, false, "a synchronous answer of an opened dialog is delivered")

  -- on_answer fires once only
  local count = 0
  kit.ask({
    question = "once",
    on_answer = function()
      count = count + 1
    end,
  })
  confirm.confirm()
  confirm.cancel()
  eq(count, 1, "on_answer fires exactly once")
  close_all()
end
