-- Test code: when something here comes back nil, this file must crash and
-- name it rather than silently skip -- see TESTS/ui_kit_spec.lua's header.
---@diagnostic disable: need-check-nil
-- TESTS/ui_kit_ask_modal_spec.lua -- lib.nvim.ui.kit.confirm.ask waits for ANY modal kit dialog
-- (input, select, ... not only a confirm), is woken by the close instead of polling, takes a
-- `choices` list and ends the wait with a single timer. Port of ui.nvim's spec of the same name.

return function(_)
  local kit = require("lib.nvim.ui.kit")
  local confirm = require("lib.nvim.ui.kit.confirm")
  local modal = require("lib.nvim.ui.kit.modal")
  local api = vim.api

  local function eq(actual, expected, msg)
    assert(
      vim.deep_equal(actual, expected),
      ("%s: expected %s, got %s"):format(msg, vim.inspect(expected), vim.inspect(actual))
    )
  end
  local function ok(cond, msg)
    assert(cond, msg)
  end
  local function wait_for(fn, msg)
    ok(vim.wait(800, fn, 5), msg)
  end
  local function idle(ms)
    vim.wait(ms, function()
      return false
    end, 5)
  end
  local function close_all()
    confirm.close()
    for _, w in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_is_valid(w) and api.nvim_win_get_config(w).relative ~= "" then
        pcall(api.nvim_win_close, w, true)
      end
    end
  end

  -- the registry follows the float
  eq(modal.busy(), false, "nothing open at the start")
  local input =
    kit.input({ prompt = "name", on_submit = function() end, on_cancel = function() end })
  ok(input, "an input opened")
  eq(modal.busy(), true, "an open input is a modal dialog")
  input:close()
  eq(modal.busy(), false, "and no longer once its float is closed")

  -- ask waits for an open INPUT (before: only a confirm counted, the question covered the input)
  local blocker =
    kit.input({ prompt = "typing", on_submit = function() end, on_cancel = function() end })
  local answer
  kit.ask({
    question = "ask while typing?",
    on_answer = function(yes)
      answer = yes
    end,
  })
  idle(60)
  eq(confirm.is_open(), false, "ask does not open on top of an open input")
  eq(answer, nil, "and has not answered")
  blocker:close()
  wait_for(function()
    return confirm.is_open()
  end, "the question opens once the input is gone")
  confirm.confirm()
  eq(answer, true, "and is answered")

  -- ask waits for an open SELECT
  local picked
  local sel = kit.select({
    items = { "a", "b" },
    on_select = function(item)
      picked = item
    end,
    on_cancel = function() end,
  })
  ok(sel ~= nil or modal.busy(), "a select opened")
  eq(modal.busy(), true, "an open select is a modal dialog")
  answer = nil
  kit.ask({
    question = "ask while choosing?",
    on_answer = function(yes)
      answer = yes
    end,
  })
  idle(60)
  eq(confirm.is_open(), false, "ask does not open on top of an open select")
  close_all()
  wait_for(function()
    return confirm.is_open()
  end, "the question opens once the select is gone")
  confirm.cancel()
  eq(answer, false, "and a cancel is a no")
  eq(picked, nil, "the select was not answered by the question")

  -- a list of choices: the label comes back, a cancel is nil
  local got = "none"
  kit.ask({
    question = "which?",
    choices = { "Build", "Skip" },
    on_answer = function(c)
      got = c
    end,
  })
  ok(confirm.is_open(), "an ask with choices shows at once when nothing is open")
  confirm.move(1)
  confirm.confirm()
  eq(got, "Skip", "the focused label is answered")
  kit.ask({
    question = "which?",
    choices = { "Build", "Skip" },
    on_answer = function(c)
      got = c
    end,
  })
  confirm.cancel()
  eq(got, nil, "a cancel answers nil for a choices list")

  -- starved: a choices ask is answered nil, a plain one false
  confirm.open({ question = "never answered", on_answer = function() end })
  local starved_choice = "none"
  local starved_yes
  kit.ask({
    question = "starved choices",
    choices = { "a", "b" },
    max_wait_ms = 40,
    on_answer = function(c)
      starved_choice = c
    end,
  })
  kit.ask({
    question = "starved yes/no",
    max_wait_ms = 40,
    on_answer = function(y)
      starved_yes = y
    end,
  })
  wait_for(function()
    return starved_choice ~= "none" and starved_yes ~= nil
  end, "starved questions are answered")
  eq(starved_choice, nil, "a starved choices ask answers nil")
  eq(starved_yes, false, "a starved yes/no ask answers false")
  close_all()

  -- nothing polls: while it waits an ask arms exactly one timer (its wait limit)
  local orig_defer, calls = vim.defer_fn, 0
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.defer_fn = function(fn, ms)
    calls = calls + 1
    return orig_defer(fn, ms)
  end
  confirm.open({ question = "blocker", on_answer = function() end })
  local waiting_answer
  kit.ask({
    question = "waits quietly",
    on_answer = function(y)
      waiting_answer = y
    end,
  })
  idle(120)
  vim.defer_fn = orig_defer
  eq(calls, 1, "one timer for the whole wait, no polling")
  confirm.close()
  wait_for(function()
    return confirm.is_open()
  end, "and it still opens when the blocker goes")
  confirm.confirm()
  eq(waiting_answer, true, "answered")

  -- abandoned while waiting: dropped, the timer does not answer for it later
  local dropped_called = false
  local b2 =
    kit.input({ prompt = "typing", on_submit = function() end, on_cancel = function() end })
  local gone = false
  kit.ask({
    question = "dropped",
    max_wait_ms = 80,
    abandoned = function()
      return gone
    end,
    on_answer = function()
      dropped_called = true
    end,
  })
  gone = true
  b2:close()
  idle(200)
  eq(
    dropped_called,
    false,
    "an abandoned question is dropped unasked and never answered by the timer"
  )
  eq(confirm.is_open(), false, "and nothing is shown")
  close_all()
end
