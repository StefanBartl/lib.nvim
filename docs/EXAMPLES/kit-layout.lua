-- docs/EXAMPLES/kit-layout.lua
--
-- Module:   lib.nvim.ui.kit.layout (lib.nvim.ui.kit.layout)
-- Scenario: hand-build your own coordinated multi-float layout instead of
--           using a ready-made template like "picker" (kit-picker.lua).
--           This is the "three windows that line up perfectly" primitive
--           everything else in the kit's layout engine is built on:
--           `compute` is pure geometry math (no I/O, unit-testable),
--           `mount` turns that geometry into real themed surfaces.

local kit = require("lib.nvim.ui.kit")

-- 1. COMPUTE -- describe the layout as nested rows/cols of relative (<=1,
-- a fraction of the parent) or fixed (>1, cells) sizes. Pure function: no
-- window is opened yet, so this is safe to call from anywhere, including a
-- unit test, to sanity-check the geometry.
local spec = {
  width = 0.8,
  height = 0.8,
  gap = 0,
  rows = {
    { name = "header", height = 3 },
    {
      cols = {
        { name = "list", width = 0.35 },
        { name = "detail", width = 0.65 },
      },
    },
  },
}

local geo = kit.layout.compute(spec)
-- `geo.slots` is a table keyed by slot name -> nvim_open_win-ready geometry
-- ({ row, col, width, height, relative, ... }) for "header", "list", and
-- "detail"; `geo.outer` is the bounding box all of them sit inside.
-- Inspect `geo.slots` directly if you want to feed it into your own
-- nvim_open_win calls instead of `mount`.
vim.notify(
  ("list slot: row=%d col=%d w=%d h=%d"):format(
    geo.slots.list.row,
    geo.slots.list.col,
    geo.slots.list.width,
    geo.slots.list.height
  )
)

-- 2. MOUNT -- the same spec, but this time it actually opens themed
-- surfaces for every named slot and returns a group handle.
local group = kit.layout.mount(spec, {
  theme = "rounded",
  enter = "list", -- which slot receives focus on open
})

group.slots.header:set_lines({ "Search results" })
group.slots.list:set_lines({ "result 1", "result 2", "result 3" })
group.slots.detail:set_lines({ "Select a result to see details here." })

-- Move the cursor in "list" and update "detail" accordingly -- wiring this
-- up by hand is exactly what kit.picker (kit-picker.lua) already does for
-- the common "prompt drives results" case; reach for `layout` directly
-- when your UI doesn't fit that shape (here: no prompt at all, just two
-- panes that need to stay in sync).
vim.api.nvim_create_autocmd("CursorMoved", {
  buffer = group.slots.list.bufnr,
  callback = function()
    local line = vim.api.nvim_win_get_cursor(group.slots.list.winid)[1]
    group.slots.detail:set_lines({ ("Details for result %d"):format(line) })
  end,
})

-- Closing the group closes every slot's window at once:
vim.keymap.set("n", "q", group.close, { buffer = group.slots.list.bufnr })
