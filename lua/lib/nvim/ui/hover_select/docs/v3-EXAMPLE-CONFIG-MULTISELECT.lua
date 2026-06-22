---@module 'example.hover_select_multiselect'
---@description Example demonstrating multi-selection feature in hover-select

local notify = require("lib.nvim.notify").create("[lib.nvim.ui.hover_select.docs.v3-EXAMPLE-CONFIG-MULTISELECT]")

local hover_select = require("lib.nvim.ui.hover_select")

---Example 1: Single-select mode (backward compatible)
local function example_single_select()
  local items = {
    "Option A",
    "Option B",
    "Option C",
  }

  hover_select.open({
    title = "Single Selection",
    items = items,
    multi_select = false,  -- Default behavior
    on_select = function(selected, index)
      notify.info(string.format("You selected: %s (line %d)", selected, index))
    end,
  })
end

---Example 2: Multi-select mode
local function example_multi_select()
  local tasks = {
    "Update documentation",
    "Fix bug #123",
    "Refactor module X",
    "Write unit tests",
    "Review PR #456",
  }

  hover_select.open({
    title = "Select tasks to complete (Tab to mark)",
    items = tasks,
    multi_select = true,
    ---@param selected string[]
    ---@param indices string[]
    on_select = function(selected, indices)
      -- Handle array results
      if #selected == 1 then
        notify.info("Completing 1 task: " .. selected[1])
      else
        local msg = { string.format("Completing %d tasks:", #selected) }
        for i, task in ipairs(selected) do
          table.insert(msg, string.format("  %d. [line %d] %s", i, indices[i], task))
        end
        notify.info(table.concat(msg, "\n"))
      end
    end,
  })
end

---Example 3: File processing with multi-select
local function example_file_batch_processing()
  local files = {
    "src/init.lua",
    "src/config.lua",
    "src/utils.lua",
    "src/core/state.lua",
    "src/ui/window.lua",
    "tests/test_init.lua",
  }

  hover_select.open({
    title = "Select files to format",
    items = files,
    multi_select = true,
    width = 50,
    height = 8,
    ---@param selected_files string[]
    on_select = function(selected_files, _)
      -- Simulate batch processing
      local results = {}
      for _, file in ipairs(selected_files) do
        table.insert(results, string.format("✓ Formatted %s", file))
      end

      notify.info(string.format( "Batch Processing Results (%d files):\n%s", #selected_files, table.concat(results, "\n") ))
    end,
  })
end

---Example 4: Integration with existing gather results
local function example_gather_integration()
  -- Simulate gather results (functions from scan)
  local function_results = {
    "15:4: M.setup",
    "23:2: run_gatherer",
    "45:6: format_output",
    "67:0: validate_input",
    "89:2: process_results",
  }

  hover_select.open({
    title = "Navigate to functions (multi-select)",
    items = function_results,
    multi_select = true,
    ---@param selections string[]
    on_select = function(selections, _)
      -- Parse and navigate to each selected function
      for _, selection in ipairs(selections) do
        local line_num = selection:match("^(%d+):")
        local func_name = selection:match(": (.+)$")

        -- In real implementation, this would:
        -- 1. Parse file path from context
        -- 2. Open file
        -- 3. Jump to line number
        notify.info(string.format("Navigate to %s at line %s", func_name, line_num))
      end
    end,
  })
end

---Example 5: Dynamic callback based on selection count
local function example_dynamic_behavior()
  local operations = {
    "git commit",
    "git push",
    "git pull",
    "git rebase",
    "git merge",
  }

  hover_select.open({
    title = "Git Operations",
    items = operations,
    multi_select = true,
    ---@param selected string[]
    on_select = function(selected, _)
      if #selected == 1 then
        -- Single operation: execute immediately
        vim.notify("Executing: " .. selected[1], vim.log.levels.INFO)
        -- execute_git_command(selected[1])
      else
        -- Multiple operations: ask for confirmation
        local confirm_msg = string.format(
          "Execute %d operations?\n%s",
          #selected,
          table.concat(selected, "\n")
        )

        local confirmed = vim.fn.confirm(confirm_msg, "&Yes\n&No", 1)
        if confirmed == 1 then
          notify.info("Executing batch operations...")
          -- for _, op in ipairs(selected) do
          --   execute_git_command(op)
          -- end
        end
      end
    end,
  })
end

-- Export examples
return {
  single_select = example_single_select,
  multi_select = example_multi_select,
  file_batch = example_file_batch_processing,
  gather_integration = example_gather_integration,
  dynamic_behavior = example_dynamic_behavior,
}
