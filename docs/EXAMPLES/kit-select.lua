-- docs/EXAMPLES/kit-select.lua
--
-- Module:   lib.nvim.ui.kit.select (lib.nvim.ui.kit.select)
-- Scenario: a themed list chooser -- single or multi-select -- for picking
--           one (or several) items out of a short list. Navigation is
--           j/k/arrows, <CR> selects, <Esc>/q cancels; multi-select adds
--           <Tab> to toggle a mark.

local kit = require("lib.nvim.ui.kit")

-- Single select: `on_select(item, idx)` fires once, with the chosen item
-- and its 1-based index into `selection`.
kit.select({
  title = "Pick a branch",
  selection = { "main", "develop", "feature/x" },
  on_select = function(choice, idx)
    vim.notify(("checked out %s (#%d)"):format(choice, idx))
  end,
})

-- Multi-select: `on_select(items, indices)` instead -- both arrays, even
-- when only one item was toggled.
kit.select({
  title = "Stage files",
  selection = { "a.lua", "b.lua", "c.lua" },
  multi = true,
  on_select = function(items, indices)
    vim.notify(("staged %d file(s): %s"):format(#items, table.concat(items, ", ")))
  end,
})

-- Selecting arbitrary objects, not just strings, is fine as long as the
-- list itself renders sensibly -- pair with a `format`-style presentation
-- at the call site, or pre-format the display strings before passing them
-- in (kit.select itself has no `format` option, unlike harvest.sink.select
-- -- format before you call it):
local branches = {
  { name = "main", ahead = 0 },
  { name = "wip/refactor", ahead = 12 },
}
local labels = {}
for i, b in ipairs(branches) do
  labels[i] = ("%s (%d ahead)"):format(b.name, b.ahead)
end
kit.select({
  title = "Branches",
  selection = labels,
  on_select = function(_, idx)
    vim.notify("picked: " .. branches[idx].name)
  end,
})
