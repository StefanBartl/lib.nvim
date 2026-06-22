---@module 'lib.nvim.ui.hover_select.navigation'
---@description Navigation and keymap setup for lib.nvim.ui.hover_select buffer

local notify = require("lib.nvim.notify").create("[lib.nvim.ui.hover_select.navigation]")

local M = {}

local api = vim.api
local set_km = vim.keymap.set

---Setup navigation keymaps for the given buffer
---@param bufnr integer Buffer number
---@param on_select function Callback to execute on selection
---@param on_toggle function|nil Callback to toggle line selection (multi-select mode)
function M.setup(bufnr, on_select, on_toggle)
  local opts = { noremap = true, silent = true, buffer = bufnr }

  -- Block horizontal movement in all modes
  M._block_horizontal_movement(bufnr)

  -- Vertical movement (keep default behavior)
  -- j/k, <Up>/<Down>, etc. work normally

  -- Multi-select with Tab (if callback provided)
  if on_toggle then
    -- Tab: Toggle current line and stay
    set_km("n", "<Tab>", function()
      local ok, err = pcall(on_toggle)
      if not ok then
        notify.error("Toggle error: " .. tostring(err))
      end
    end, opts)

    -- Shift-Tab: Toggle current line and move up
    set_km("n", "<S-Tab>", function()
      local ok, err = pcall(function()
        on_toggle()
        -- Move cursor up after toggle
        local winid = api.nvim_get_current_win()
        if api.nvim_win_is_valid(winid) then
          local cursor = api.nvim_win_get_cursor(winid)
          local new_line = cursor[1] - 1
          if new_line < 1 then
            new_line = api.nvim_buf_line_count(bufnr)
          end
          api.nvim_win_set_cursor(winid, { new_line, 0 })
        end
      end)
      if not ok then
        notify.error("Shift-Tab error: " .. tostring(err))
      end
    end, opts)

    -- Also map in insert mode (switch to normal mode first)
    set_km("i", "<Tab>", function()
      vim.cmd("stopinsert")
      vim.defer_fn(function()
        local ok = pcall(on_toggle)
        if not ok then
          notify.error("Toggle error in insert mode")
        end
      end, 10)
    end, opts)

    set_km("i", "<S-Tab>", function()
      vim.cmd("stopinsert")
      vim.defer_fn(function()
        on_toggle()
        local winid = api.nvim_get_current_win()
        if api.nvim_win_is_valid(winid) then
          local cursor = api.nvim_win_get_cursor(winid)
          local new_line = cursor[1] - 1
          if new_line < 1 then
            new_line = api.nvim_buf_line_count(bufnr)
          end
          api.nvim_win_set_cursor(winid, { new_line, 0 })
        end
      end, 10)
    end, opts)
  else
    -- If no toggle callback, disable Tab/Shift-Tab to prevent accidental actions
    local noop = function() end
    set_km("n", "<Tab>", noop, opts)
    set_km("n", "<S-Tab>", noop, opts)
    set_km("i", "<Tab>", noop, opts)
    set_km("i", "<S-Tab>", noop, opts)
  end

  -- Selection with Enter
  set_km("n", "<CR>", function()
    local ok, err = pcall(on_select)
    if not ok then
      notify.error("Selection error: " .. tostring(err))
    end
  end, opts)

  set_km("n", "<2-LeftMouse>", function()
    local ok, err = pcall(on_select)
    if not ok then
      notify.error("Selection error: " .. tostring(err))
    end
  end, opts)

  -- Close with Escape or q
  set_km("n", "<Esc>", function()
    local hover_select = require("lib.nvim.ui.hover_select")
    hover_select.close()
  end, opts)

  set_km("n", "q", function()
    local hover_select = require("lib.nvim.ui.hover_select")
    hover_select.close()
  end, opts)
end

---Block horizontal cursor movement in all modes
---@param bufnr integer Buffer number
---@private
function M._block_horizontal_movement(bufnr)
  local noop = function() end
  local modes = { "n", "v", "i" }
  local horizontal_keys = {
    "h",
    "l",
    "<Left>",
    "<Right>",
    "0",
    "^",
    "$",
    "w",
    "e",
    "b",
    "W",
    "E",
    "B",
  }

  for _, mode in ipairs(modes) do
    for _, key in ipairs(horizontal_keys) do
      set_km(mode, key, noop, {
        noremap = true,
        silent = true,
        buffer = bufnr,
      })
    end
  end
end

---@type Lib.UI.HoverSelect.Navigation
return M
