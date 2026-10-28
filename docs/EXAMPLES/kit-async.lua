-- docs/EXAMPLES/kit-async.lua
--
-- Module:   lib.nvim.ui.kit.async (ui.kit.async in ui.nvim)
-- Scenario: ask the user several things in a row as plain linear code -- an input, then a
--           confirm that uses the answer -- without nesting callbacks and without blocking
--           Neovim. (A blocking `vim.wait` bridge cannot work: typed keys are not run during
--           vim.wait, so the dialog would never see them.)
--
-- Every kit.async.* call must be made inside kit.async.run(function() ... end); outside it there
-- is nothing to suspend and the call raises. A cancelled dialog gives what its callback form
-- gives: input and form return nil, true; confirm returns false (nil for a choices list).

local kit = require("lib.nvim.ui.kit")

kit.async.run(function()
  local name, cancelled = kit.async.input({ prompt = "File name" })
  if cancelled or not name or name == "" then
    return
  end

  local yes = kit.async.confirm({ question = ("Create %s?"):format(name) })
  if yes then
    vim.notify("creating " .. name)
  end

  -- a choice between a few actions: the answer is the label, nil when dismissed
  local what = kit.async.confirm({
    question = "Open it afterwards?",
    choices = { "Open", "Leave" },
  })
  if what == "Open" then
    vim.notify("opening " .. name)
  end
end)

-- A question that should wait behind whatever dialog is open (a stream that ends later):
kit.async.run(function()
  if kit.async.ask({ question = "File the answer?" }) then
    vim.notify("filed")
  end
end)
