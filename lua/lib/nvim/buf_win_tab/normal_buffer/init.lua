---@module 'lib.nvim.buf_win_tab.normal_buffer'
---Shared buffer/window primitives around "normal" file buffers.
---
---A *normal file buffer* is a real, listed, loaded buffer backed by a readable
---file on disk — i.e. not a terminal, tree, help, prompt or scratch buffer.
---These helpers are used by Neo-tree and the LazyGit bridge to find the editor
---window to replace, edit in place without stealing focus, and optionally
---prompt before discarding unsaved changes.

require("lib.nvim.buf_win_tab.normal_buffer.@types")

local api = vim.api
local fn = vim.fn

local M = {}

---Whether `bufnr` is a real, listed file buffer backed by a readable file.
---@param bufnr? integer Buffer number (0 or nil = current buffer)
---@return boolean
function M.is_normal_file_buffer(bufnr)
  bufnr = (bufnr == nil or bufnr == 0) and api.nvim_get_current_buf() or bufnr

  if not api.nvim_buf_is_valid(bufnr) then
    return false
  end
  if not api.nvim_buf_is_loaded(bufnr) then
    return false
  end
  -- Skip special buffers (terminal, help, prompt, nofile, …).
  if api.nvim_get_option_value("buftype", { buf = bufnr }) ~= "" then
    return false
  end
  -- Skip hidden/internal buffers.
  if not api.nvim_get_option_value("buflisted", { buf = bufnr }) then
    return false
  end

  local name = api.nvim_buf_get_name(bufnr)
  if name == nil or name == "" then
    return false
  end
  -- Must be a real file on disk, not an unsaved [No Name]/new buffer.
  return fn.filereadable(name) == 1
end

---Find the most recently laid-out window in the current tabpage that shows a
---normal file buffer. Iterates windows in reverse so the last editor window
---wins; terminal floats, trees and other special buffers are skipped.
---@param exclude_win? integer Window id to ignore (e.g. the Neo-tree window)
---@return integer|nil bufnr Buffer shown in the matched window
---@return integer|nil winid Matched window id
function M.find_last_normal_window(exclude_win)
  local wins = api.nvim_tabpage_list_wins(0)

  for i = #wins, 1, -1 do
    local win = wins[i]
    if win ~= exclude_win and api.nvim_win_is_valid(win) then
      local buf = api.nvim_win_get_buf(win)
      if M.is_normal_file_buffer(buf) then
        return buf, win
      end
    end
  end

  return nil, nil
end

---`:edit {path}` inside `winid` via `nvim_win_call`, without changing focus.
---@param winid integer Target window
---@param path string File path to open
---@return boolean ok
---@return string|nil err Error message when `ok` is false
function M.edit_in_window(winid, path)
  if not api.nvim_win_is_valid(winid) then
    return false, "invalid window id"
  end
  if type(path) ~= "string" or path == "" then
    return false, "invalid path"
  end

  local ok, err = pcall(api.nvim_win_call, winid, function()
    vim.cmd("edit " .. fn.fnameescape(path))
  end)
  if not ok then
    return false, tostring(err)
  end
  return true, nil
end

---Interactive, blocking save prompt for a buffer with unsaved changes.
---Returns true when it is safe to proceed (buffer was clean, saved, or the user
---chose to discard); returns false only when the user cancelled.
---
---Blocking via `vim.fn.confirm` — do NOT call this while a terminal float (e.g.
---LazyGit) owns the screen, as the prompt would be invisible.
---@param bufnr integer
---@return boolean proceed
function M.prompt_save(bufnr)
  if not api.nvim_buf_is_valid(bufnr) then
    return true
  end
  if not api.nvim_get_option_value("modified", { buf = bufnr }) then
    return true
  end

  local name = api.nvim_buf_get_name(bufnr)
  local label = name ~= "" and fn.fnamemodify(name, ":t") or ("buffer " .. bufnr)

  local choice = fn.confirm(
    string.format("Save changes to %s?", label),
    "&Yes\n&No\n&Cancel",
    1
  )

  if choice == 1 then
    -- Save in the buffer's own context without changing focus.
    local ok = pcall(api.nvim_buf_call, bufnr, function()
      vim.cmd("write")
    end)
    return ok
  elseif choice == 2 then
    -- Discard: proceed without saving.
    return true
  end

  -- 3 (Cancel) or 0 (Esc): abort.
  return false
end

---@type Lib.BufWinTab.NormalBuffer
return M
