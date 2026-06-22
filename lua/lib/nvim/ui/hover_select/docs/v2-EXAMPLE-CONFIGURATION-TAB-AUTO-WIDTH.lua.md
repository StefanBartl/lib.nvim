---@module 'example.hover_select_v2_configuration'
---@description Example demonstrating new v2 features: Tab navigation and auto-width

local hover_select = require("lib.nvim.ui.hover_select")

-- ============================================================================
-- Example 1: Basic Usage with Tab Navigation
-- ============================================================================

local function example_basic_with_tab()
  hover_select.open({
    title = "Choose Tool",
    items = {
      "functions",
      "tables",
      "strings",
    },
    use_tab_navigation = true,  -- Enable Tab/Shift-Tab
    on_select = function(selected, index)
      vim.notify(string.format("Selected: %s (index %d)", selected, index))
    end,
  })
end

-- ============================================================================
-- Example 2: Auto-Width for Long Content
-- ============================================================================

local function example_auto_width()
  hover_select.open({
    title = "File Operations",
    items = {
      "Create new file in current directory",
      "Open existing file from project root",
      "Delete selected file permanently (no undo)",
      "Rename file with validation",
    },
    auto_width = true,  -- Window sizes to longest line
    use_tab_navigation = true,
    on_select = function(selected)
      vim.notify("Action: " .. selected)
    end,
  })
end

-- ============================================================================
-- Example 3: Wrap Mode for Very Long Lines
-- ============================================================================

local function example_wrap_mode()
  hover_select.open({
    title = "Warning",
    items = {
      "This is a very long warning message that would be too wide for a fixed window and should wrap instead of extending beyond the screen boundary",
      "Cancel",
    },
    auto_width = "wrap",  -- Enable line wrapping
    width = 40,           -- Fixed width, content wraps
    use_tab_navigation = true,
    on_select = function(selected)
      if selected == "Cancel" then
        vim.notify("Operation cancelled")
      else
        vim.notify("Proceeding with operation")
      end
    end,
  })
end

-- ============================================================================
-- Example 4: Confirmation Dialog (Like gather CWD confirm)
-- ============================================================================

local function example_confirmation_dialog()
  local stats = {
    files = 523,
    dirs = 45,
    lines = 87432,
    est_time = 6,
  }

  local message = string.format(
    "Scan %d files in %d directories (~%d lines)?",
    stats.files,
    stats.dirs,
    stats.lines
  )

  hover_select.open({
    title = "Confirm Scan",
    items = {
      message,
      "",
      string.format("⏱️  Estimated time: ~%d seconds", stats.est_time),
      "",
      "✓ Yes, proceed",
      "✗ No, cancel",
    },
    auto_width = true,  -- Size to fit the longest line
    use_tab_navigation = true,
    on_select = function(selected)
      if selected:match("^✓") then
        vim.notify("Starting scan...")
        -- Proceed with operation
      elseif selected:match("^✗") then
        vim.notify("Cancelled")
      end
    end,
  })
end

-- ============================================================================
-- Example 5: Multi-Column Display (Future-Proof for Multi-Select)
-- ============================================================================

local function example_future_multiselect()
  hover_select.open({
    title = "Select Language (Tab to navigate, Space to toggle in future)",
    items = {
      "[ ] Lua",
      "[ ] Python",
      "[ ] JavaScript",
      "[ ] TypeScript",
      "[ ] Rust",
    },
    use_tab_navigation = true,  -- Tab for navigation
    -- Note: Tab is NOT used for selection, leaving it available
    -- for future multi-select toggle functionality
    on_select = function(selected)
      vim.notify("Selected: " .. selected)
    end,
  })
end

-- ============================================================================
-- Example 6: Fixed Width vs Auto-Width Comparison
-- ============================================================================

local function example_width_comparison()
  -- First, show fixed width
  hover_select.open({
    title = "Fixed Width (40 chars)",
    items = {
      "Short",
      "Medium length item here",
      "This is a very long item that extends beyond the window",
    },
    width = 40,
    -- auto_width not set (default: fixed)
    on_select = function(selected)
      -- Then show auto-width
      vim.defer_fn(function()
        hover_select.open({
          title = "Auto Width (fits content)",
          items = {
            "Short",
            "Medium length item here",
            "This is a very long item that extends beyond the window",
          },
          auto_width = true,  -- Automatically sizes to longest line
          on_select = function(sel)
            vim.notify("Selected: " .. sel)
          end,
        })
      end, 50)
    end,
  })
end

-- ============================================================================
-- Run Examples
-- ============================================================================

-- Uncomment to test:
-- example_basic_with_tab()
-- example_auto_width()
-- example_wrap_mode()
-- example_confirmation_dialog()
-- example_future_multiselect()
-- example_width_comparison()

return {
  basic_with_tab = example_basic_with_tab,
  auto_width = example_auto_width,
  wrap_mode = example_wrap_mode,
  confirmation = example_confirmation_dialog,
  future_multiselect = example_future_multiselect,
  width_comparison = example_width_comparison,
}
