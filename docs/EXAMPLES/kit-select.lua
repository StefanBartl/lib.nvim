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

-- Rich items: a multi-line entry with per-column highlight groups. Mix
-- freely with plain strings in the same list --
-- on_select still hands back exactly what you put in. Navigation (j/k/<CR>)
-- moves by logical item, landing on `anchor` (default: the item's first
-- line), so a 3-line item is still one up/down step, not three.
kit.select({
  title = "Chain suggestions",
  items = {
    {
      lines = { "-> my_chain (12 hits)", "  local alias = my_chain", "" },
      highlights = {
        { line = 0, col_start = 0, col_end = 2, hl_group = "Special" }, -- the "->" arrow
        { line = 0, col_start = 3, col_end = 12, hl_group = "Identifier" }, -- chain name
        { line = 1, hl_group = "Statement" }, -- whole line (col_end omitted)
      },
    },
    {
      lines = { "-> other_chain (4 hits)", "  local other = other_chain", "" },
      highlights = {
        { line = 0, col_start = 0, col_end = 2, hl_group = "Special" },
        { line = 0, col_start = 3, col_end = 15, hl_group = "Identifier" },
        { line = 1, hl_group = "Statement" },
      },
    },
  },
  on_select = function(item)
    vim.notify("picked: " .. item.lines[1])
  end,
})
