---@module 'lib.nvim.ui.hover_select.test_multiselect'
---@description Test functions for hover_select multi-selection feature

local notify = require("lib.nvim.notify").create("[lib.nvim.ui.hover_select.test_multiselect]")

local hover_select = require("lib.nvim.ui.hover_select")

local M = {}

--- Test single-select mode (default behavior)
function M.test_single_select()
  local items = {
    "Option A",
    "Option B",
    "Option C",
    "Option D",
    "Option E",
  }

  hover_select.open({
    title = "Single Select Test",
    items = items,
    multi_select = false, -- Explicit single-select
    on_select = function(selected, index)
      notify.info(string.format("Selected: %s (index: %d)", selected, index))
    end,
  })
end

--- Test multi-select mode
function M.test_multi_select()
  local items = {
    "Item 1",
    "Item 2",
    "Item 3",
    "Item 4",
    "Item 5",
    "Item 6",
  }

  hover_select.open({
    title = "Multi Select Test (Tab to toggle)",
    items = items,
    multi_select = true,
    ---@param selected string[]
    ---@param indices string[]
    on_select = function(selected, indices)
      -- Handle array results
      local msg_lines = { "Selected items:" }
      for i, item in ipairs(selected) do
        table.insert(msg_lines, string.format("  [%d] %s", indices[i], item))
      end

      notify.info(table.concat(msg_lines, "\n"))
    end,
  })
end

--- Test multi-select with longer list
function M.test_multi_select_long()
  local items = {}
  for i = 1, 20 do
    table.insert(items, string.format("Entry %02d", i))
  end

  hover_select.open({
    title = "Multi Select Long List",
    items = items,
    multi_select = true,
    height = 15,
    ---@param selected string[]
    on_select = function(selected, _)
      notify.info(string.format("Selected %d items: %s", #selected, table.concat(selected, ", ")))
    end,
  })
end

--- Test multi-select with no selections (should select current line)
function M.test_multi_select_no_selection()
  local items = {
    "First",
    "Second",
    "Third",
  }

  hover_select.open({
    title = "Press Enter without Tab",
    items = items,
    multi_select = true,
    on_select = function(selected, indices)
      notify.info(string.format("No Tab pressed - auto-selected current line:\n [%d] %s", indices[1], selected[1]))
    end,
  })
end

--- Test integration: gather-style use case
function M.test_file_list()
  local files = {
    "lua/init.lua",
    "lua/config.lua",
    "lua/utils.lua",
    "lua/core/state.lua",
    "lua/core/buffer.lua",
    "lua/ui/window.lua",
  }

  hover_select.open({
    title = "Select files to process",
    items = files,
    multi_select = true,
    ---@param selected string[]
    on_select = function(selected, _)
      local msg = { "Processing files:" }
      for _, file in ipairs(selected) do
        table.insert(msg, "  • " .. file)
      end
      notify.info(table.concat(msg, "\n"))
    end,
  })
end

--- Run all tests sequentially
function M.run_all()
  notify.info("Test 1: Single Select")
  vim.defer_fn(function()
    M.test_single_select()
  end, 100)
end

return M
