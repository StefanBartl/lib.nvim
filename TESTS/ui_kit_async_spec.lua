-- Test code: when something here comes back nil, this file must crash and
-- name it rather than silently skip -- see TESTS/ui_kit_spec.lua's header.
---@diagnostic disable: need-check-nil
-- TESTS/ui_kit_async_spec.lua -- lib.nvim.ui.kit.async: coroutines over the callback components
-- (confirm, ask, input, form, select) without blocking Neovim. Port of ui.nvim's spec of the same
-- name; the typed-keys spec of a child Neovim with a UI lives in ui.nvim only.

return function(_)
  local kit = require("lib.nvim.ui.kit")
  local async = kit.async
  local confirm = require("lib.nvim.ui.kit.confirm")

  local function eq(actual, expected, msg)
    assert(
      vim.deep_equal(actual, expected),
      ("%s: expected %s, got %s"):format(msg, vim.inspect(expected), vim.inspect(actual))
    )
  end
  local function ok(cond, msg)
    assert(cond, msg)
  end

  confirm.close()

  -- outside a coroutine: an error that names run
  local called, err = pcall(async.confirm, { question = "x" })
  eq(called, false, "outside a coroutine it raises")
  ok(tostring(err):find("kit.async.run", 1, true), "and names kit.async.run: " .. tostring(err))

  -- confirm: suspends, resumes with the answer
  local got
  async.run(function()
    got = { async.confirm({ question = "Delete?" }) }
  end)
  ok(confirm.is_open(), "the dialog is open while the coroutine waits")
  eq(got, nil, "and the coroutine has not got past it")
  confirm.confirm()
  eq(got, { true }, "Yes -> true")

  async.run(function()
    got = { async.confirm({ question = "Delete?" }) }
  end)
  confirm.cancel()
  eq(got, { false }, "cancel -> false")

  async.run(function()
    got = { async.confirm({ question = "Which?", choices = { "Build", "Skip" } }) }
  end)
  confirm.move(1)
  confirm.confirm()
  eq(got, { "Skip" }, "choices -> the label")

  async.run(function()
    got = { async.confirm({ question = "Which?", choices = { "Build", "Skip" } }) }
  end)
  confirm.cancel()
  eq(got, {}, "choices cancel -> nil (nothing after the call)")
  got = nil

  -- ask: waits its turn, answers
  async.run(function()
    got = { async.ask({ question = "Really?" }) }
  end)
  ok(confirm.is_open(), "ask shows at once when nothing is open")
  confirm.confirm()
  eq(got, { true }, "ask -> true")

  -- a dialog that answers while it is being opened is returned without suspending
  local sync_result
  async.run(function()
    sync_result = {
      async.await(function(deliver)
        deliver("now", 2)
      end),
    }
  end)
  eq(sync_result, { "now", 2 }, "an answer given inside start is returned at once, all values")

  -- only the first delivery counts
  local second
  async.run(function()
    second = {
      async.await(function(deliver)
        vim.schedule(function()
          deliver("first")
          deliver("second")
        end)
      end),
    }
  end)
  ok(
    vim.wait(500, function()
      return second ~= nil
    end, 5),
    "the delayed delivery arrives"
  )
  eq(second, { "first" }, "a second delivery is ignored")

  -- select: the item and its index, nil on dismiss
  local stub_select = package.loaded["lib.nvim.ui.kit.select"]
  local real_open = stub_select.open
  stub_select.open = function(o)
    o.on_select(o.items[2], 2)
  end
  local picked
  async.run(function()
    picked = { async.select({ items = { "a", "b" } }) }
  end)
  eq(picked, { "b", 2 }, "select -> item, index")
  stub_select.open = function(o)
    o.on_cancel()
  end
  async.run(function()
    picked = { async.select({ items = { "a", "b" } }) }
  end)
  eq(picked, {}, "select dismissed -> nil")
  stub_select.open = real_open

  -- input / form: value, or nil and true when cancelled; the caller's own callbacks still run
  local input_mod = package.loaded["lib.nvim.ui.kit.input"]
  local real_input = input_mod.open
  local user_called
  input_mod.open = function(o)
    o.on_submit("typed")
  end
  async.run(function()
    got = {
      async.input({
        prompt = "p",
        on_submit = function(v)
          user_called = v
        end,
      }),
    }
  end)
  eq(got, { "typed", false }, "input -> value, false")
  eq(user_called, "typed", "the caller's own on_submit ran too")
  input_mod.open = function(o)
    o.on_cancel()
  end
  async.run(function()
    got = { async.input({ prompt = "p" }) }
  end)
  eq(got[1], nil, "input cancelled -> nil")
  eq(got[2], true, "and cancelled = true")
  input_mod.open = real_input

  -- an error in the coroutine is reported with its traceback, not swallowed
  local notified
  local real_notify = vim.notify
  vim.notify = function(msg)
    notified = msg
  end
  async.run(function()
    error("boom in the coroutine")
  end)
  vim.wait(200, function()
    return notified ~= nil
  end, 5)
  vim.notify = real_notify
  ok(notified and notified:find("boom in the coroutine", 1, true), "the error is reported")
  ok(notified:find("ui.kit.async", 1, true), "and says where it comes from")

  -- an error raised after a suspension is reported too, and does not reach the dialog's callback
  local notified2
  vim.notify = function(msg)
    notified2 = msg
  end
  async.run(function()
    async.confirm({ question = "then fail" })
    error("after the dialog")
  end)
  local resumed_ok = pcall(confirm.confirm)
  vim.wait(200, function()
    return notified2 ~= nil
  end, 5)
  vim.notify = real_notify
  eq(resumed_ok, true, "the answer's callback does not raise into the dialog")
  ok(notified2 and notified2:find("after the dialog", 1, true), "the late error is reported")

  confirm.close()
end
