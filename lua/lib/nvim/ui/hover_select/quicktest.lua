---@module 'lib.nvim.ui.hover_select.quicktest'
---@description Quick test for hover_select multi-selection

-- Run this with: :luafile lua/lib/hover_select/quicktest.lua

local hover_select = require("lib.nvim.ui.hover_select")

-- Test 1: Single-Select (default)
local function test_single()
  hover_select.open({
    title = "Single Select Test",
    items = { "Option A", "Option B", "Option C" },
    on_select = function(selected, index)
      print(string.format("Selected: %s (index: %d)", selected, index))
    end,
  })
end

-- Test 2: Multi-Select
local function test_multi()
  hover_select.open({
    title = "Multi Select Test (Tab to toggle)",
    items = {
      "Item 1",
      "Item 2",
      "Item 3",
      "Item 4",
      "Item 5",
    },
    multi_select = true,  -- Enable multi-select
    ---@param selected string[]
    ---@param indices string[]
    on_select = function(selected, indices)
      -- selected is array, indices is array
      print(string.format("Selected %d items:", #selected))
      for i, item in ipairs(selected) do
        print(string.format("  [%d] %s", indices[i], item))
      end
    end,
  })
end

-- Create user commands for easy testing
vim.api.nvim_create_user_command('HoverTestSingle', test_single, {})
vim.api.nvim_create_user_command('HoverTestMulti', test_multi, {})

print([[
Hover Select Quick Test loaded!

Commands:
  :HoverTestSingle  - Test single-select mode
  :HoverTestMulti   - Test multi-select mode (use Tab to mark lines)

Usage in multi-select:
  Tab      - Toggle current line
  Shift-Tab - Toggle and move up
  Enter    - Confirm selection
  Esc/q    - Cancel
]])

-- Auto-run multi-select test
vim.defer_fn(test_multi, 100)
