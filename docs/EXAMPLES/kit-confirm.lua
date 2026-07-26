-- docs/EXAMPLES/kit-confirm.lua
--
-- Module:   lib.nvim.ui.kit.confirm (lib.nvim.ui.kit.confirm)
-- Scenario: a question answered with a row of horizontal buttons instead
--           of a vertical list -- h/l (or arrows/<Tab>) move focus between
--           buttons, <CR> confirms the focused one, <Esc>/q cancels.
--           Same answer contract as `kit.prompt`'s confirm mode: default
--           Yes/No -> boolean, custom `choices` -> string.

local kit = require("lib.nvim.ui.kit")

-- Default Yes/No buttons: on_answer(boolean). Cancelling (<Esc>/q) also
-- calls on_answer(false) for the default two-choice case.
kit.confirm({
  question = "Delete 3 files?",
  on_answer = function(yes)
    if yes then
      require("myplugin").delete_files()
    end
  end,
})

-- Custom buttons: on_answer(choice_string). Cancelling calls
-- on_answer(nil) instead of a "Cancel" string, so you can tell "the user
-- explicitly picked Cancel" apart from "the user pressed Esc" if that
-- distinction matters to you.
kit.confirm({
  question = "Overwrite existing file?",
  choices = { "Overwrite", "Rename", "Skip" },
  on_answer = function(choice)
    if choice == nil then
      return -- <Esc>/q -- treat like "Skip" without being told to
    end
    require("myplugin").resolve_conflict(choice)
  end,
})

-- Reachable through the generic dispatch front door too, if you already
-- have a `type`-driven call site (see kit-note.lua for the same pattern):
kit.popup({
  type = "prompt",
  answer_type = "confirm",
  layout = "buttons", -- this is what routes a "prompt" popup to kit.confirm
  question = "Proceed?",
  on_answer = function(yes) end,
})
