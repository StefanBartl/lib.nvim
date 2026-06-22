---@module 'lib.nvim.ui.hover_select'
---@description Main module for creating interactive hover selection windows
---with line-wise navigation, multi-selection, and custom selection callbacks

local notify = require("lib.nvim.notify").create("[lib.nvim.ui.hover_select]")

local lazy = require("lib.lua.lazy")

---@type Lib.UI.HoverSelect.Config.Module
local config = lazy.require("lib.nvim.ui.hover_select.config")

---@type Lib.UI.HoverSelect.Buffer
local buffer = lazy.require("lib.nvim.ui.hover_select.buffer")

---@type Lib.UI.HoverSelect.Window
local window = lazy.require("lib.nvim.ui.hover_select.window")

---@type Lib.UI.HoverSelect.Navigation
local navigation = lazy.require("lib.nvim.ui.hover_select.navigation")

---@type Lib.UI.HoverSelect.Highlight
local highlight = lazy.require("lib.nvim.ui.hover_select.highlight")

local M = {}

local api = vim.api

---@type Lib.HoverSelect.State
local state = {
  bufnr = nil,
  winid = nil,
  items = {},
  on_select = nil,
  multi_select = false,
  selections = {},
  ns_id = api.nvim_create_namespace("hover_select"),
}

-- ============================================================================
-- Public API
-- ============================================================================

--- Open a new hover selection window.
--- Creates buffer and floating window, initializes state,
--- sets up navigation, highlights and callbacks.
---
---@param opts Lib.HoverSelect.Options
---@return integer|nil bufnr  # Buffer number on success
---@return integer|nil winid  # Window id on success
function M.open(opts)
  -- Validate required parameters
  if not opts or not opts.items or #opts.items == 0 then
    notify.error("lib.nvim.ui.hover_select: items list is required and must not be empty")
    return nil, nil
  end

  if not opts.on_select or type(opts.on_select) ~= "function" then
    notify.error("lib.nvim.ui.hover_select: on_select callback is required")
    return nil, nil
  end

  -- Close any existing instance
  M.close()

  -- Extract configuration options
  local use_tab_navigation = opts.use_tab_navigation or false
  local auto_width = opts.auto_width  -- Can be true, "wrap", or nil/false

  -- Merge user options with defaults
  local merged_buf_opts = vim.tbl_deep_extend("force", config.default_buf_options, opts.buf_options or {})
  local merged_win_opts = vim.tbl_deep_extend("force", config.default_win_options, opts.win_options or {})

  -- Create buffer with items
  local bufnr = buffer.create(opts.items, merged_buf_opts)
  if not bufnr then
    return nil, nil
  end

  -- Calculate dimensions
  local win_config = {
    relative = opts.relative or "cursor",
    width = opts.width,
    height = opts.height,
    title = opts.title,
    items_count = #opts.items,
  }

  -- Create floating window (pass items for auto-width calculation if window.create supports it)
  local winid
  if type(window.create) == "function" then
    -- Check if window.create accepts additional parameters
    local create_params = debug.getinfo(window.create, "u").nparams
    if create_params >= 5 then
      winid = window.create(bufnr, win_config, merged_win_opts, opts.items, auto_width)
    else
      winid = window.create(bufnr, win_config, merged_win_opts)
    end
  else
    winid = window.create(bufnr, win_config, merged_win_opts)
  end

  if not winid then
    api.nvim_buf_delete(bufnr, { force = true })
    return nil, nil
  end

  -- Store state
  state.bufnr = bufnr
  state.winid = winid
  state.items = opts.items
  state.on_select = opts.on_select
  state.multi_select = opts.multi_select or false
  state.selections = {}

  -- Setup highlight for current line
  highlight.setup(winid)

  -- Setup navigation keymaps
  local on_toggle = nil

  -- Multi-select mode: Tab toggles selection
  if state.multi_select then
    on_toggle = function()
      M._toggle_selection()
    end
  -- Legacy use_tab_navigation mode: Tab for navigation (deprecated in favor of j/k)
  elseif use_tab_navigation then
    -- Note: use_tab_navigation is deprecated. Use j/k for navigation.
    -- This is kept for backward compatibility.
    on_toggle = function()
      -- Simple navigation without toggle
      local winid_local = api.nvim_get_current_win()
      if not api.nvim_win_is_valid(winid_local) then
        return
      end

      local buf = api.nvim_win_get_buf(winid_local)
      local cursor = api.nvim_win_get_cursor(winid_local)
      local line_count = api.nvim_buf_line_count(buf)

      local next_line = cursor[1] + 1
      if next_line > line_count then
        next_line = 1
      end

      api.nvim_win_set_cursor(winid_local, { next_line, 0 })
    end
  end

  navigation.setup(bufnr, function()
    M._handle_selection()
  end, on_toggle)

  -- Set cursor to first line
  api.nvim_win_set_cursor(winid, { 1, 0 })

  return bufnr, winid
end

---Close the hover selection window and clean up resources
function M.close()
  if state.winid and api.nvim_win_is_valid(state.winid) then
    api.nvim_win_close(state.winid, true)
  end

  if state.bufnr and api.nvim_buf_is_valid(state.bufnr) then
    -- Clear highlights before deleting
    highlight.clear_marks(state.bufnr, state.ns_id)
    api.nvim_buf_delete(state.bufnr, { force = true })
  end

  -- Clear state
  state.bufnr = nil
  state.winid = nil
  state.items = {}
  state.on_select = nil
  state.multi_select = false
  state.selections = {}
end

---Check if hover selection window is currently open
---@return boolean is_open True if window is open and valid
function M.is_open()
  return state.winid ~= nil and api.nvim_win_is_valid(state.winid)
end

-- ============================================================================
-- Internal helpers
-- ============================================================================

--- Toggle selection state of the current line.
--- Only relevant in multi-select mode.
---@private
function M._toggle_selection()
  if not state.winid or not api.nvim_win_is_valid(state.winid) then
    return
  end

  if not state.bufnr or not api.nvim_buf_is_valid(state.bufnr) then
    return
  end

  -- Get current cursor position
  local cursor = api.nvim_win_get_cursor(state.winid)
  local line_idx = cursor[1]

  -- Toggle selection
  state.selections[line_idx] = not state.selections[line_idx]

  -- Update highlights
  M._update_selection_highlights()
end

---Update visual highlights for all selected lines
---@private
function M._update_selection_highlights()
  if not state.bufnr or not api.nvim_buf_is_valid(state.bufnr) then
    return
  end

  -- Clear existing marks
  highlight.clear_marks(state.bufnr, state.ns_id)

  -- Collect selected line numbers
  local selected_lines = {}
  for line_idx, selected in pairs(state.selections) do
    if selected then
      table.insert(selected_lines, line_idx)
    end
  end

  -- Mark selected lines
  if #selected_lines > 0 then
    highlight.mark_selected(state.bufnr, state.ns_id, selected_lines)
  end
end

---Handle selection of current line or multiple lines
---@private
function M._handle_selection()
  if not state.winid or not api.nvim_win_is_valid(state.winid) then
    return
  end

  -- Get current cursor position
  local cursor = api.nvim_win_get_cursor(state.winid)
  local line_idx = cursor[1]

  -- Store callback before closing (window close might clear state)
  local callback = state.on_select
  local multi_mode = state.multi_select

  if multi_mode then
    -- Multi-select mode: return all selected items (or current if none selected)
    local selected_items = {}
    local selected_indices = {}

    -- Check if any items are selected
    local has_selections = false
    for _, selected in pairs(state.selections) do
      if selected then
        has_selections = true
        break
      end
    end

    if has_selections then
      -- Return all selected items (sorted by index)
      local sorted_indices = {}
      for idx, selected in pairs(state.selections) do
        if selected and state.items[idx] then
          table.insert(sorted_indices, idx)
        end
      end
      table.sort(sorted_indices)

      for _, idx in ipairs(sorted_indices) do
        table.insert(selected_items, state.items[idx])
        table.insert(selected_indices, idx)
      end
    else
      -- No selections: return current line
      if state.items[line_idx] then
        table.insert(selected_items, state.items[line_idx])
        table.insert(selected_indices, line_idx)
      end
    end

    -- Close window and buffer
    M.close()

    -- Execute callback with arrays
    if callback and #selected_items > 0 then
      callback(selected_items, selected_indices)
    end

  else
    -- Single-select mode: return current item
    local selected_item = state.items[line_idx]
    if not selected_item then
      notify.warn("lib.nvim.ui.hover_select: invalid selection")
      M.close()
      return
    end

    -- Close window and buffer
    M.close()

    -- Execute callback
    if callback then
      callback(selected_item, line_idx)
    end
  end
end


---@type Lib.UI.HoverSelect
return M
