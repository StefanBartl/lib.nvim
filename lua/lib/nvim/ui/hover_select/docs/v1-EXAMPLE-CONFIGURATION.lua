---@module 'example.hover_select_configuration'
---@description Example configuration demonstrating how to create a hover-select instance with all supported options

-- This file demonstrates how a plugin or module could configure and
-- create a hover-select UI with custom options. It is not part of the
-- core implementation and serves documentation purposes only.
require("lib.nvim.ui.hover_select.@types")

-- Import the main hover-select module
local hover_select = require("lib.nvim.ui.hover_select")

-- Example items to display in the selection window
---@type string[]
local items = {
  "Option A",
  "Option B",
  "Option C",
  "Option D",
}

-- Callback executed when the user selects an item
---@param selected string The selected item text
---@param index integer The 1-based index of the selected item
local function on_select(selected, index)
  -- In a real plugin, this could trigger further logic
  vim.notify(
    string.format("Selected item %d: %s", index, selected),
    vim.log.levels.INFO
  )
end

-- Complete hover-select options table
---@type Lib.HoverSelect.Options
local opts = {
  -- List of items to display (one per line)
  items = items,

  -- Callback invoked on selection
  on_select = on_select,

  -- Optional buffer-local options
  -- These are merged with the default buffer options
  buf_options = {
    -- Disable undo history for the buffer
    undolevels = -1,

    -- Prevent accidental edits
    modifiable = false,
  },

  -- Optional window-local options
  -- These are merged with the default window options
  win_options = {
    -- Highlight the current line
    cursorline = true,

    -- Ensure no line numbers are shown
    number = false,
    relativenumber = false,
  },

  -- Optional window title (requires a border)
  title = "Select an option",

  -- Positioning of the floating window
  -- Possible values depend on Neovim: "cursor", "win", "editor"
  relative = "cursor",

  -- Optional explicit width and height
  -- If omitted, values are auto-calculated
  width = 40,
  height = 6,
}

-- Create and show the hover-select UI
-- The exact function name may differ depending on the public API
-- of lib.nvim.ui.hover_select (for example: open, show, or create)
hover_select.open(opts)
