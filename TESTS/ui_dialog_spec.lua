-- Test code: when something here comes back nil, this file must crash and
-- name it rather than silently skip -- see TESTS/ui_kit_spec.lua's header.
---@diagnostic disable: need-check-nil
-- TESTS/ui_dialog_spec.lua -- lib.nvim.ui.dialog: one wrapper over ui.kit / the lib copy / native.
-- Every backend, every function, and the contract: the callback runs once and never before the
-- call has returned.

return function(H)
  local eq, ok = H.eq, H.ok
  local api = vim.api

  local function same(actual, expected, msg)
    ok(
      vim.deep_equal(actual, expected),
      ("%s: expected %s, got %s"):format(msg, vim.inspect(expected), vim.inspect(actual))
    )
  end
  local function wait_for(fn, msg)
    ok(vim.wait(800, fn, 5), msg)
  end
  local function idle(ms)
    vim.wait(ms, function()
      return false
    end, 5)
  end

  local restores = {}
  --- Put `value` in `tbl[key]` for the rest of the spec; everything is restored at the end.
  local function stub(tbl, key, value)
    restores[#restores + 1] = { tbl, key, tbl[key] }
    tbl[key] = value
  end

  --- `require("ui.kit")` raises (ui.nvim not installed).
  local function without_ui_kit()
    stub(package.loaded, "ui.kit", nil)
    stub(package.preload, "ui.kit", function()
      error("module 'ui.kit' not found")
    end)
  end

  --- A kit that records what it was asked and answers when the test says so.
  local function fake_kit()
    local kit = { confirm_calls = {}, ask_calls = {}, input_calls = {} }
    kit.confirm = function(o)
      kit.confirm_calls[#kit.confirm_calls + 1] = o
      return {}
    end
    kit.ask = function(o)
      kit.ask_calls[#kit.ask_calls + 1] = o
    end
    kit.input = function(o)
      kit.input_calls[#kit.input_calls + 1] = o
      return {}
    end
    return kit
  end

  local ok_body, err_body = pcall(function()
    local dialog = require("lib.nvim.ui.dialog")
    stub(package.loaded, "ui.kit", nil)

    -- ------------------------------------------------------------ backend 1: ui.kit
    local ui_kit = fake_kit()
    stub(package.loaded, "ui.kit", ui_kit)
    eq(dialog.backend(), "ui.kit", "ui.kit is preferred when it loads")

    local got = {}
    local used = dialog.confirm({
      question = "Delete?",
      default = 2,
      kind = "danger",
      on_answer = function(v)
        got[#got + 1] = v
      end,
    })
    eq(used, "ui.kit", "confirm reports the backend")
    eq(#ui_kit.confirm_calls, 1, "the question went to ui.kit")
    eq(ui_kit.confirm_calls[1].question, "Delete?", "with its question")
    eq(ui_kit.confirm_calls[1].default, 2, "and the options of the kit")
    eq(ui_kit.confirm_calls[1].kind, "danger", "kind too")
    ui_kit.confirm_calls[1].on_answer(true)
    ui_kit.confirm_calls[1].on_answer(false)
    same(got, { true }, "answered once, a second answer from the kit is ignored")

    -- an answer given while the dialog is being opened waits for the next turn
    ui_kit.confirm = function(o)
      o.on_answer(true)
      return {}
    end
    got = {}
    dialog.confirm({
      question = "At once?",
      on_answer = function(v)
        got[#got + 1] = v
      end,
    })
    same(got, {}, "not called before confirm() returned")
    wait_for(function()
      return #got > 0
    end, "an answer given while opening arrives on the next turn")
    same(got, { true }, "exactly once")

    -- ask goes to kit.ask
    got = {}
    used = dialog.ask({
      question = "Later?",
      on_answer = function(v)
        got[#got + 1] = v
      end,
    })
    eq(used, "ui.kit", "ask uses the kit's queued question")
    eq(#ui_kit.ask_calls, 1, "kit.ask got it")
    ui_kit.ask_calls[1].on_answer(false)
    same(got, { false }, "and its answer")

    -- input: callback style (vim.ui.input) and kit style
    got = {}
    used = dialog.input({ prompt = "Name", default = "x" }, function(v)
      got[#got + 1] = v == nil and "nil" or v
    end)
    eq(used, "ui.kit", "input goes to ui.kit")
    eq(ui_kit.input_calls[1].default, "x", "with its options")
    ui_kit.input_calls[1].on_submit("typed")
    ui_kit.input_calls[1].on_cancel()
    same(got, { "typed" }, "callback style: the value, once")
    got = {}
    dialog.input({ prompt = "Name" }, function(v)
      got[#got + 1] = v == nil and "nil" or v
    end)
    ui_kit.input_calls[2].on_cancel()
    same(got, { "nil" }, "callback style: nil when cancelled")
    local submitted, cancelled
    dialog.input({
      prompt = "Kit style",
      on_submit = function(v)
        submitted = v
      end,
      on_cancel = function()
        cancelled = true
      end,
    })
    ui_kit.input_calls[3].on_submit("kit")
    eq(submitted, "kit", "kit style: on_submit")
    dialog.input({
      prompt = "Kit style",
      on_submit = function(v)
        submitted = v
      end,
      on_cancel = function()
        cancelled = true
      end,
    })
    ui_kit.input_calls[4].on_cancel()
    eq(cancelled, true, "kit style: on_cancel")

    -- choose: the answer is the index, 0 when dismissed; the type colours the border
    ui_kit.confirm = fake_kit().confirm
    ui_kit.confirm_calls = {}
    local recording = ui_kit.confirm
    ui_kit.confirm = function(o)
      ui_kit.confirm_calls[#ui_kit.confirm_calls + 1] = o
      return recording(o)
    end
    got = {}
    used = dialog.choose("Save?", "&Save\n&Discard\n&Cancel", 2, function(i)
      got[#got + 1] = i
    end, "Warning")
    eq(used, "ui.kit", "choose rides on confirm")
    local c = ui_kit.confirm_calls[#ui_kit.confirm_calls]
    eq(c.default, 2, "the default button")
    eq(c.kind, "warn", "Warning -> warn")
    eq(c.choices, "&Save\n&Discard\n&Cancel", "the choices string goes to the kit as it is")
    c.on_answer("Discard")
    same(got, { 2 }, "the index of the label without the &")
    got = {}
    dialog.choose("Save?", { "a", "b" }, 0, function(i)
      got[#got + 1] = i
    end)
    ui_kit.confirm_calls[#ui_kit.confirm_calls].on_answer(nil)
    same(got, { 0 }, "dismissed -> 0")
    eq(ui_kit.confirm_calls[#ui_kit.confirm_calls].default, 1, "default 0 starts on the first")

    -- ------------------------------------------------------------ backend 2: the copy in lib.nvim
    without_ui_kit()
    eq(dialog.backend(), "lib.nvim.ui.kit", "without ui.nvim the copy of lib.nvim answers")
    local lib_kit = require("lib.nvim.ui.kit")
    local confirm = require("lib.nvim.ui.kit.confirm")
    confirm.close()
    idle(20)

    got = {}
    used = dialog.choose("Remove?", "&Delete\n&Cancel", 2, function(i)
      got[#got + 1] = i
    end)
    eq(used, "lib.nvim.ui.kit", "a real dialog of the lib copy")
    ok(confirm.is_open(), "which is open")
    same(got, {}, "unanswered so far")
    api.nvim_feedkeys(api.nvim_replace_termcodes("d", true, false, true), "x", false)
    same(got, { 1 }, "the hotkey picks the first button: index 1")
    ok(not confirm.is_open(), "and the dialog is gone")

    got = {}
    dialog.confirm({
      question = "Sure?",
      on_answer = function(v)
        got[#got + 1] = v
      end,
    })
    confirm.cancel()
    same(got, { false }, "dismissed -> false")

    got = {}
    dialog.choose("Which?", { "a", "b" }, 1, function(i)
      got[#got + 1] = i
    end)
    confirm.cancel()
    same(got, { 0 }, "choose dismissed -> 0")

    -- the lib copy's input
    got = {}
    local s_input = lib_kit.input
    stub(lib_kit, "input", function(o)
      vim.schedule(function()
        o.on_submit("from the lib copy")
      end)
      return {}
    end)
    dialog.input({ prompt = "x" }, function(v)
      got[#got + 1] = v
    end)
    wait_for(function()
      return #got > 0
    end, "the lib copy's input answers")
    same(got, { "from the lib copy" }, "its value")
    lib_kit.input = s_input

    -- ------------------------------------------------------------ backend 3: native
    stub(package.loaded, "lib.nvim.ui.kit", {}) -- loads, but is no kit
    eq(dialog.backend(), "native", "no kit loads -> native")
    local asked = {}
    stub(vim.ui, "select", function(items, opts, on_choice)
      asked[#asked + 1] = { items = items, prompt = opts.prompt }
      on_choice(items[#items], #items)
    end)

    got = {}
    used = dialog.confirm({
      question = "Native yes/no?",
      on_answer = function(v)
        got[#got + 1] = v
      end,
    })
    eq(used, "native", "native backend")
    same(asked[1].items, { "Yes", "No" }, "Yes/No")
    eq(asked[1].prompt, "Native yes/no?", "the question is the prompt")
    same(got, {}, "native select answered at once, still not before confirm() returned")
    wait_for(function()
      return #got > 0
    end, "and it arrives")
    same(got, { false }, "picking No -> false, once")

    -- the labels of a vim.fn.confirm string, cleaned the way the kit cleans them
    asked = {}
    got = {}
    dialog.choose("Pick", "Fish && Chips\n&Cancel\n", 1, function(i)
      got[#got + 1] = i
    end)
    same(asked[1].items, { "Fish & Chips", "Cancel" }, "&& literal, & dropped, empty piece skipped")
    wait_for(function()
      return #got > 0
    end, "native choose answers")
    same(got, { 2 }, "the index of the picked label")

    -- ask without a kit falls back to the same native question
    got = {}
    used = dialog.ask({
      question = "Native ask?",
      on_answer = function(v)
        got[#got + 1] = v
      end,
    })
    eq(used, "native", "ask has a native path too")
    wait_for(function()
      return #got > 0
    end, "native ask answers")

    -- native input, plain and secret
    local seen_input
    stub(vim.ui, "input", function(opts, on_confirm)
      seen_input = opts
      on_confirm("typed natively")
    end)
    got = {}
    used = dialog.input({ prompt = "Name", default = "d", completion = "file" }, function(v)
      got[#got + 1] = v
    end)
    eq(used, "native", "native input")
    eq(seen_input.prompt, "Name", "prompt")
    eq(seen_input.default, "d", "default")
    eq(seen_input.completion, "file", "completion")
    same(got, {}, "not before input() returned")
    wait_for(function()
      return #got > 0
    end, "native input answers")
    same(got, { "typed natively" }, "once")
    stub(vim.fn, "inputsecret", function()
      return "hunter2"
    end)
    got = {}
    dialog.input({ prompt = "Password", secret = true }, function(v)
      got[#got + 1] = v
    end)
    wait_for(function()
      return #got > 0
    end, "native secret input answers")
    same(got, { "hunter2" }, "a secret goes through inputsecret")

    -- ------------------------------------------------------------ a float that cannot open
    stub(package.loaded, "lib.nvim.ui.kit", {
      confirm = function(o)
        o.on_answer(false) -- what the kit does when its float cannot be created
        return nil
      end,
      input = function(o)
        return nil
      end,
    })
    eq(dialog.backend(), "lib.nvim.ui.kit", "the kit loads...")
    asked = {}
    got = {}
    used = dialog.confirm({
      question = "No float?",
      on_answer = function(v)
        got[#got + 1] = v
      end,
    })
    eq(used, "native", "...but its float did not open: the question goes native")
    eq(#asked, 1, "asked once, natively")
    wait_for(function()
      return #got > 0
    end, "native answer arrives")
    same(got, { false }, "once (the kit's own 'no' was not delivered on top of it)")
    seen_input = nil
    got = {}
    used = dialog.input({ prompt = "No float" }, function(v)
      got[#got + 1] = v
    end)
    eq(used, "native", "input falls back as well")
    wait_for(function()
      return #got > 0
    end, "native input answers")
    same(got, { "typed natively" }, "once")
  end)

  for i = #restores, 1, -1 do
    local r = restores[i]
    r[1][r[2]] = r[3]
  end
  require("lib.nvim.ui.kit.confirm").close()
  if not ok_body then
    error(err_body, 0)
  end
end
