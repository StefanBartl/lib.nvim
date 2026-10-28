-- TESTS/ui_kit_dialog_hook_spec.lua -- kit.set_dialog_hook: a test answers confirm, ask, input, select,
-- form and sheet without a window; without a hook (or when the hook passes) nothing changes.

return function(H)
  local eq, ok = H.eq, H.ok
  local function same(actual, expected, msg)
    if not vim.deep_equal(actual, expected) then
      error(
        ("FAIL %s: expected %s, got %s"):format(msg, vim.inspect(expected), vim.inspect(actual)),
        2
      )
    end
  end
  local kit = require("lib.nvim.ui.kit")

  --- Floating windows open right now.
  local function floats()
    local n = 0
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(w).relative ~= "" then
        n = n + 1
      end
    end
    return n
  end

  --- Wait for `box.done`.
  local function settle(box)
    vim.wait(500, function()
      return box.done
    end, 5)
  end

  local before = floats()
  local seen = {}
  --- Answer by kind from `answers`; remember what was asked.
  local function install(answers)
    kit.set_dialog_hook(function(kind, opts)
      seen[#seen + 1] = { kind = kind, question = opts.question or opts.prompt or opts.title }
      local a = answers[kind]
      if a == nil then
        return false
      end
      return true, a.value
    end)
  end

  eq(kit.get_dialog_hook(), nil, "no hook by default")

  -- confirm: a plain question, yes by index and by boolean, no, and a dismissal
  install({ confirm = { value = 1 } })
  local box = {}
  local surf = kit.confirm({
    question = "Delete?",
    on_answer = function(yes)
      box.done, box.yes = true, yes
    end,
  })
  ok(surf ~= nil, "confirm: a stand-in surface comes back (a nil would read as 'could not open')")
  eq(box.done, nil, "confirm: the answer does not come before the call has returned")
  settle(box)
  eq(box.yes, true, "confirm: index 1 is a yes")
  eq(floats(), before, "confirm: no window opened")
  eq(seen[1].kind, "confirm", "confirm: the hook is told the kind")
  eq(seen[1].question, "Delete?", "confirm: ...and sees the caller's options")

  for value, expected in pairs({ [2] = false, [false] = false }) do
    install({ confirm = { value = value } })
    box = {}
    kit.confirm({
      question = "x",
      on_answer = function(yes)
        box.done, box.yes = true, yes
      end,
    })
    settle(box)
    eq(box.yes, expected, "confirm: " .. tostring(value) .. " is a no")
  end
  install({ confirm = { value = true } })
  box = {}
  kit.confirm({
    question = "x",
    on_answer = function(yes)
      box.done, box.yes = true, yes
    end,
  })
  settle(box)
  eq(box.yes, true, "confirm: true is a yes")

  -- confirm with choices: an index or a label, nil dismisses
  for _, case in ipairs({
    { value = 2, label = "Discard", index = 2 },
    { value = "Cancel", label = "Cancel", index = 3 },
    { value = nil, label = nil, index = nil },
  }) do
    install({ confirm = { value = case.value } })
    box = {}
    kit.confirm({
      question = "Save?",
      choices = "&Save\n&Discard\n&Cancel",
      on_answer = function(label, index)
        box.done, box.label, box.index = true, label, index
      end,
    })
    settle(box)
    eq(box.label, case.label, "confirm choices: label for " .. tostring(case.value))
    eq(box.index, case.index, "confirm choices: index for " .. tostring(case.value))
  end

  -- ask
  install({ ask = { value = "Yes" } })
  box = {}
  kit.ask({
    question = "File it?",
    choices = { "No", "Yes" },
    on_answer = function(label, index)
      box.done, box.label, box.index = true, label, index
    end,
  })
  settle(box)
  same({ box.label, box.index }, { "Yes", 2 }, "ask: answered by label")
  eq(seen[#seen].kind, "ask", "ask: the hook is told the kind")

  -- input: a text, and a dismissal
  install({ input = { value = "typed" } })
  box = {}
  surf = kit.input({
    prompt = "Name",
    on_submit = function(text)
      box.done, box.text = true, text
    end,
    on_cancel = function()
      box.done, box.cancelled = true, true
    end,
  })
  ok(surf ~= nil, "input: a stand-in surface comes back")
  settle(box)
  eq(box.text, "typed", "input: on_submit gets the text")
  install({ input = { value = nil } })
  box = {}
  kit.input({
    prompt = "Name",
    on_submit = function()
      box.done = true
    end,
    on_cancel = function()
      box.done, box.cancelled = true, true
    end,
  })
  settle(box)
  eq(box.cancelled, true, "input: nil is a cancel")

  -- select: by index, by item, nil, and a multi selection
  local items = { "alpha", "beta", "gamma" }
  for _, case in ipairs({ { 2, "beta", 2 }, { "gamma", "gamma", 3 } }) do
    install({ select = { value = case[1] } })
    box = {}
    kit.select({
      items = items,
      on_select = function(item, idx)
        box.done, box.item, box.idx = true, item, idx
      end,
    })
    settle(box)
    same({ box.item, box.idx }, { case[2], case[3] }, "select: " .. tostring(case[1]))
  end
  install({ select = { value = nil } })
  box = {}
  kit.select({
    items = items,
    on_select = function() end,
    on_cancel = function()
      box.done, box.cancelled = true, true
    end,
  })
  settle(box)
  eq(box.cancelled, true, "select: nil is a cancel")
  install({ select = { value = { 1, "gamma" } } })
  box = {}
  kit.select({
    items = items,
    multi = true,
    on_select = function(picked, at)
      box.done, box.picked, box.at = true, picked, at
    end,
  })
  settle(box)
  same(box.picked, { "alpha", "gamma" }, "select multi: the items")
  same(box.at, { 1, 3 }, "select multi: and their indexes")

  -- form and sheet: the keyed table, and a dismissal
  for _, kind in ipairs({ "form", "sheet" }) do
    install({ [kind] = { value = { name = "x" } } })
    box = {}
    kit[kind]({
      fields = { { name = "name", label = "Name" } },
      on_submit = function(values)
        box.done, box.values = true, values
      end,
      on_cancel = function()
        box.done, box.cancelled = true, true
      end,
    })
    settle(box)
    same(box.values, { name = "x" }, kind .. ": on_submit gets the table")
    install({ [kind] = { value = nil } })
    box = {}
    kit[kind]({
      fields = { { name = "name", label = "Name" } },
      on_submit = function()
        box.done = true
      end,
      on_cancel = function()
        box.done, box.cancelled = true, true
      end,
    })
    settle(box)
    eq(box.cancelled, true, kind .. ": nil is a cancel")
  end
  eq(floats(), before, "no window opened for any of them")

  -- a hook that passes leaves the dialog to the real component; an error of the hook is the caller's
  kit.set_dialog_hook(function()
    return false
  end)
  box = {}
  local real = kit.confirm({
    question = "Real?",
    on_answer = function(yes)
      box.done, box.yes = true, yes
    end,
  })
  ok(real ~= nil and real.hooked == nil, "a hook that passes: the real dialog opens")
  eq(floats(), before + 1, "...as a window")
  require("lib.nvim.ui.kit.confirm").close()
  settle(box)
  eq(box.yes, false, "...and closing it answers 'no'")

  kit.set_dialog_hook(function()
    error("no answer for this dialog")
  end)
  local raised, err = pcall(kit.confirm, { question = "x", on_answer = function() end })
  eq(raised, false, "an error of the hook is raised in the caller")
  ok(tostring(err):find("no answer for this dialog", 1, true), "...with its message")

  -- removing the hook restores the normal behaviour
  kit.set_dialog_hook(nil)
  eq(kit.get_dialog_hook(), nil, "the hook is gone")
  real = kit.confirm({ question = "Real again?", on_answer = function() end })
  ok(real ~= nil and real.hooked == nil, "without a hook the real dialog opens")
  require("lib.nvim.ui.kit.confirm").close()
  vim.wait(100)
end
