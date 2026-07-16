---@module 'lib.nvim.buf_win_tab.selection'
--- Read the visual selection, whether or not visual mode is still active.
---
--- While in visual mode the selection is bounded by the `v` mark and the
--- cursor; once visual mode has ended it is bounded by the `'<` / `'>` marks.
--- `get_visual_selection` handles both, so a mapping works the same whether
--- it fires from a visual-mode `:` command (which leaves visual mode first)
--- or from a `vim.keymap.set("v", ...)` callback (which does not).
---
--- Rows are 1-based (Vim convention); columns are 1-based and inclusive on
--- both ends, matching `string.sub` so slices can be taken directly.

require("lib.nvim.buf_win_tab.selection.@types")

local M = {}

---Read the current (or most recent) visual selection.
---@return Lib.BufWinTab.Selection|nil # `nil` when no usable selection exists
function M.get_visual_selection()
  local mode = vim.fn.mode()
  local is_visual = mode:match("^[vV\22]") ~= nil

  local start_pos, end_pos
  if is_visual then
    -- Live selection: the `v` mark is the anchor, `.` is the cursor.
    start_pos = vim.fn.getpos("v")
    end_pos = vim.fn.getpos(".")
  else
    start_pos = vim.fn.getpos("'<")
    end_pos = vim.fn.getpos("'>")
  end

  local start_row, start_col = start_pos[2], start_pos[3]
  local end_row, end_col = end_pos[2], end_pos[3]

  if start_row == 0 or end_row == 0 then
    return nil -- marks unset: nothing has been selected yet
  end

  -- The cursor may sit before the anchor; normalize to start <= end.
  if start_row > end_row or (start_row == end_row and start_col > end_col) then
    start_row, end_row = end_row, start_row
    start_col, end_col = end_col, start_col
  end

  local lines = vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, false)
  if #lines == 0 then
    return nil
  end

  -- Clamp the end column: in linewise mode Vim reports a huge value.
  local last_len = #lines[#lines]
  if end_col > last_len then
    end_col = last_len
  end

  if #lines == 1 then
    lines[1] = lines[1]:sub(start_col, end_col)
  else
    lines[1] = lines[1]:sub(start_col)
    lines[#lines] = lines[#lines]:sub(1, end_col)
  end

  return {
    lines = lines,
    start_row = start_row,
    start_col = start_col,
    end_row = end_row,
    end_col = end_col,
  }
end

---Re-enter visual mode over the last selection (the `gv` equivalent).
---@return boolean ok
function M.reselect_visual()
  local ok = pcall(vim.cmd, "normal! gv")
  return ok
end

---@type Lib.BufWinTab.SelectionModule
return M
