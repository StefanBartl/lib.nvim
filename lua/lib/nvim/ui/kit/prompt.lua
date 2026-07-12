---@module 'lib.nvim.ui.kit.prompt'
--- Prompt component: ask a question and collect an answer, either a yes/no
--- `confirm` (a list chooser in Phase 2; horizontal buttons arrive in Phase 4)
--- or free `text` (via the input component).

local select = require("lib.nvim.ui.kit.select")
local input = require("lib.nvim.ui.kit.input")

local M = {}

--- Open a prompt.
---@param opts table  # { question, answer_type = "confirm"|"text", choices?, default?, theme?, on_answer }
---@return any
function M.open(opts)
  opts = opts or {}
  local answer_type = opts.answer_type or "confirm"
  ---@type fun(answer: any)
  local on_answer = opts.on_answer or function(_) end

  if answer_type == "text" then
    return input.open({
      title = opts.question,
      default = opts.default,
      theme = opts.theme,
      on_submit = function(text)
        on_answer(text)
      end,
      on_cancel = function()
        on_answer(nil)
      end,
    })
  end

  -- confirm: yes/no (or a custom `choices` list). on_answer receives a boolean
  -- for the default two-choice case, or the chosen string when `choices` is set.
  local custom = type(opts.choices) == "table" and #opts.choices > 0
  local choices = custom and opts.choices or { "Yes", "No" }

  return select.open({
    title = opts.question,
    selection = choices,
    theme = opts.theme,
    on_select = function(choice, idx)
      if custom then
        on_answer(choice)
      else
        on_answer(idx == 1) -- Yes == true
      end
    end,
  })
end

return M
