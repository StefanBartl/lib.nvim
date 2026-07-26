-- docs/EXAMPLES/kit-picker.lua
--
-- Module:   lib.nvim.ui.kit.picker (lib.nvim.ui.kit.picker)
-- Scenario: a Telescope-style interactive picker -- an insert-mode prompt
--           that drives a results list as the user types, without pulling
--           in an actual fuzzy-finder dependency. <C-n>/<C-p>/arrows move
--           the selection, <CR> submits the highlighted result, <Esc>
--           closes.
--
-- kit.picker is the "wire it up for me" convenience over
-- kit.layout.template("picker", ...) -- see kit-layout.lua for the manual,
-- bring-your-own-prompt version of the same template.

local kit = require("lib.nvim.ui.kit")

-- Pretend data source: replace with a real search (files, buffers, LSP
-- symbols, ...).
local ALL_ITEMS = { "init.lua", "config.lua", "utils/strings.lua", "utils/paths.lua" }

local function fuzzy(query, items)
  if query == "" then
    return items
  end
  local out = {}
  for _, it in ipairs(items) do
    if it:lower():find(query:lower(), 1, true) then
      out[#out + 1] = it
    end
  end
  return out
end

local p
p = kit.picker({
  -- Called (debounced, default 80ms) whenever the prompt's text changes.
  -- You own the filtering; feed the result back via p.set_results().
  on_change = function(query)
    p.set_results(fuzzy(query, ALL_ITEMS))
  end,

  -- Called on <CR>, with the 1-based index and text of the highlighted
  -- result line. The picker is already closed by the time this runs.
  on_submit = function(idx, text)
    if text then
      vim.cmd.edit(vim.fn.fnameescape(text))
    end
  end,
})

-- Seed the results slot before the user types anything, so the picker
-- isn't blank on open:
if p then
  p.set_results(ALL_ITEMS)
end

-- The returned handle also exposes: p.query() (current prompt text),
-- p.move(delta) (move the selection programmatically), p.submit(),
-- p.close(), and p.slots (the raw kit.layout slot surfaces, for anything
-- this convenience wrapper doesn't cover).
