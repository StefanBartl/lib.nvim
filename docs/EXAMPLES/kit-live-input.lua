-- docs/EXAMPLES/kit-live-input.lua
--
-- Module:   lib.nvim.ui.kit.live_input (lib.nvim.ui.kit.live_input)
-- Scenario: a filter/search box that refreshes a results list on every
--           keystroke, not just on submit -- the floating prompt-buffer +
--           `TextChangedI`-debounce pattern that got hand-rolled twice in
--           filetree.nvim (`features/search/live_search/init.lua` and
--           `features/search/filter/init.lua`).

local kit = require("lib.nvim.ui.kit")

-- Live filter over a fixed candidate list, shown as a `kit.viewer` that
-- refreshes as the query changes. `on_change` only fires ~80ms (default)
-- after the last keystroke, so fast typing doesn't refire on every letter.
local candidates = { "init.lua", "confirm.lua", "input.lua", "form.lua", "menu.lua" }
local results

kit.live_input({
  title = "Filter files",
  on_change = function(query)
    local matches = {}
    for _, name in ipairs(candidates) do
      if query == "" or name:find(query, 1, true) then
        matches[#matches + 1] = name
      end
    end
    if results and results:is_valid() then
      results:set_lines(matches)
    else
      results = kit.viewer({
        title = "Matches",
        lines = matches,
        close_on_focus_lost = false,
        enter = false,
      })
    end
  end,
  on_submit = function(query)
    vim.notify("filtered on: " .. query)
  end,
  on_cancel = function()
    if results then
      results:close()
    end
  end,
})

-- A shorter debounce for something cheap to recompute on every keystroke:
kit.live_input({
  prompt = "Live",
  debounce = 30,
  on_change = function(query)
    vim.notify("query: " .. query)
  end,
})

-- routed via kit.popup({ type = "live_input" }) too:
kit.popup({
  type = "live_input",
  prompt = "Search",
  on_change = function(query) end,
})
