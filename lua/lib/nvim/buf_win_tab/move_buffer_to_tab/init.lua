---@module 'lib.nvim.buf_win_tab.move_buffer_to_tab'
-- Moves the current buffer into a new tab and removes it from the original tab
local api = vim.api

local cmd = vim.cmd
local fn = vim.fn

-- Types: see @types/init.lua (Lib.BufWinTab.MoveBufToTab).

--- Moves the current buffer to the next tab or creates a new one
---@type Lib.BufWinTab.MoveBufToTab
return function ()
  -- Get current buffer info
  local bufnr = api.nvim_get_current_buf()
  local cursor_pos = api.nvim_win_get_cursor(0)
  local original_tab = fn.tabpagenr()
  local total_tabs = fn.tabpagenr('$')
  local target_tab = original_tab + 1

  -- Find an alternate buffer to show in the original tab
  local alternate_bufnr
  if fn.bufexists("#") == 1 and fn.bufnr("#") ~= bufnr then
    alternate_bufnr = fn.bufnr("#")
  else
    -- Find any other listed buffer
    local buffers = fn.getbufinfo({buflisted = 1})
    for _, buf in ipairs(buffers) do
      if buf.bufnr ~= bufnr and buf.loaded == 1 then
        alternate_bufnr = buf.bufnr
        break
      end
    end
  end

  -- If no alternate buffer, create one
  if not alternate_bufnr then
    alternate_bufnr = api.nvim_create_buf(true, false)
  end

  -- Get all windows in the current tab and replace the buffer in each
  local tab_windows = api.nvim_tabpage_list_wins(0)
  for _, winid in ipairs(tab_windows) do
    if api.nvim_win_is_valid(winid) and api.nvim_win_get_buf(winid) == bufnr then
      api.nvim_win_set_buf(winid, alternate_bufnr)
    end
  end

  -- Move to target tab or create new one
  if target_tab <= total_tabs then
    -- Target tab exists, go there
    cmd(target_tab .. "tabnext")
    api.nvim_set_current_buf(bufnr)
  else
    -- Create a new tab at the end
    cmd("$tabnew")
    api.nvim_set_current_buf(bufnr)
  end

  -- Restore cursor position
  pcall(api.nvim_win_set_cursor, 0, cursor_pos)

  -- Clean up empty "no name" buffers across all tabs
  vim.schedule(function()
    local all_buffers = api.nvim_list_bufs()
    for _, buf in ipairs(all_buffers) do
      if api.nvim_buf_is_valid(buf) and api.nvim_buf_is_loaded(buf) then
        local name = api.nvim_buf_get_name(buf)
        local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
        local is_empty = #lines == 1 and lines[1] == ""
        local is_noname = name == ""
        local is_modified_buf = api.nvim_get_option_value('modified', { buf = buf })

        if is_noname and is_empty and not is_modified_buf then
          pcall(api.nvim_buf_delete, buf, {force = false})
        end
      end
    end
  end)
end
