-- docs/EXAMPLES/kit-prompt.lua
--
-- Module:   lib.nvim.ui.kit.prompt (lib.nvim.ui.kit.prompt)
-- Scenario: ask a question and collect one answer -- either a yes/no (or
--           custom-choice) `confirm`, or free `text`. This is the "ask,
--           get one value back" component; for a question answered with
--           horizontal buttons instead of a list, see kit-confirm.lua.

local kit = require("lib.nvim.ui.kit")

-- confirm, default choices: on_answer receives a boolean (Yes == true).
-- Renders as a vertical list chooser by default (see kit-confirm.lua for
-- the horizontal-button variant of the same question).
kit.prompt({
  question = "Delete 3 files?",
  answer_type = "confirm",
  on_answer = function(yes)
    if yes then
      require("myplugin").delete_files()
    end
  end,
})

-- confirm, custom choices: on_answer receives the chosen STRING instead of
-- a boolean.
kit.prompt({
  question = "Unsaved changes -- what now?",
  answer_type = "confirm",
  choices = { "Save", "Discard", "Cancel" },
  on_answer = function(choice)
    if choice == "Save" then
      vim.cmd.write()
    elseif choice == "Discard" then
      vim.cmd.edit({ bang = true })
    end
    -- choice == "Cancel", or the dialog was <Esc>'d (choice == nil): no-op.
  end,
})

-- text: falls through to lib.nvim.ui.kit.input under the hood. on_answer
-- receives the typed string, or nil if the prompt was cancelled.
kit.prompt({
  question = "Commit message",
  answer_type = "text",
  default = "wip",
  on_answer = function(text)
    if text then
      require("myplugin").commit(text)
    end
  end,
})
