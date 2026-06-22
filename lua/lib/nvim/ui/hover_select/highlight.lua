---@module 'lib.nvim.ui.hover_select.highlight'
---@description Highlight management for lib.nvim.ui.hover_select cursor line and multi-selection

local M = {}

local api = vim.api

---Setup highlight group for current line
---@param winid integer Window ID
function M.setup(winid)
  -- Ensure cursorline is enabled
  api.nvim_set_option_value("cursorline", true, { win = winid })

  -- Define custom highlight groups if they don't exist
  if vim.fn.hlexists("HoverSelectCursor") == 0 then
    M.define_default_highlights()
  end

  -- Link window's cursorline to custom highlight
  api.nvim_set_option_value("winhighlight", "CursorLine:HoverSelectCursor", { win = winid })
end

---Define default highlight groups
function M.define_default_highlights()
  -- Cursor line highlight
  local has_pmenu = vim.fn.hlexists("PmenuSel") == 1

  if has_pmenu then
    api.nvim_set_hl(0, "HoverSelectCursor", { link = "PmenuSel" })
  else
    -- Fallback: define custom highlight
    api.nvim_set_hl(0, "HoverSelectCursor", {
      bg = "#3e4451",
      fg = "#abb2bf",
      bold = true,
    })
  end

  -- Multi-select highlight (different from cursor)
  if vim.fn.hlexists("Visual") == 1 then
    api.nvim_set_hl(0, "HoverSelectSelected", { link = "Visual" })
  else
    -- Fallback: define custom highlight
    api.nvim_set_hl(0, "HoverSelectSelected", {
      bg = "#2c323c",
      fg = "#61afef",
    })
  end
end

---Update highlight for the given window
---@param winid integer Window ID
---@param hl_group string Highlight group name
function M.update(winid, hl_group)
  if not api.nvim_win_is_valid(winid) then
    return
  end

  api.nvim_set_option_value("winhighlight", "CursorLine:" .. hl_group, { win = winid })
end

---Mark lines as selected (multi-select mode)
---@param bufnr integer Buffer number
---@param ns_id integer Namespace ID
---@param line_numbers integer[] 1-based line numbers to mark
---@return boolean success
function M.mark_selected(bufnr, ns_id, line_numbers)
  if not api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local success = true

  for _, lnum in ipairs(line_numbers) do
    if lnum >= 1 and lnum <= api.nvim_buf_line_count(bufnr) then
      local ok = pcall(
        api.nvim_buf_add_highlight,
        bufnr,
        ns_id,
        "HoverSelectSelected",
        lnum - 1,
        0,
        -1
      )
      success = success and ok
    end
  end

  return success
end

---Clear all selection marks
---@param bufnr integer Buffer number
---@param ns_id integer Namespace ID
---@return boolean success
function M.clear_marks(bufnr, ns_id)
  if not api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local ok = pcall(api.nvim_buf_clear_namespace, bufnr, ns_id, 0, -1)
  return ok
end

---@type Lib.UI.HoverSelect.Highlight
return M
