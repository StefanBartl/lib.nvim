---@module 'lib.nvim.buffer.insert_lines'
---Utilities for inserting lines into the current buffer at typed positions

local api = vim.api


---Insert lines into the current buffer at a typed position.
---
---Semantics:
---- pos == nil            → insert at start of file
---- { cursor = true }     → insert at current cursor row
---- { row = n }           → insert at given 0-based row
---- { row = n, col = c }  → insert at given row and move cursor to col
---- { col = c, row = n }  → same as above (order independent)
---- { position = "end" }  → insert at end of file
---
---@param lines string[]
---@param pos? Lib.Buf.InsertLinesPos
local function insert_lines(lines, pos)
  local buf = 0
  local row = 0
  local col = 0

  if pos == nil then
    -- Default: insert at start of file
    row = 0
    col = 0

  elseif pos.cursor == true then
    -- Insert at current cursor position
    local win = api.nvim_get_current_win()
    local cursor = api.nvim_win_get_cursor(win)
    row = cursor[1] - 1
    col = cursor[2]

  elseif pos.position == "end" then
    -- Insert at end of file
    row = api.nvim_buf_line_count(buf)
    col = 0

  elseif pos.row ~= nil then
    -- Explicit row (with optional column)
    row = pos.row
    col = pos.col or 0

  else
    -- Fallback safety: treat as start
    row = 0
    col = 0
  end

  api.nvim_buf_set_lines(buf, row, row, false, lines)

  -- Place cursor after inserted block
  api.nvim_win_set_cursor(
    api.nvim_get_current_win(),
    { row + #lines + 1, col }
  )
end

return insert_lines

