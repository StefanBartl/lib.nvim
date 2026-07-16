---@module 'lib.nvim.window.focus_helpers'
--- Small helpers for log/output-style floating or split windows: keeping the
--- view scrolled to the bottom as content streams in, and forcing focus onto
--- a window that may be behind another or momentarily non-focusable.

local M = {}

---Move the cursor to the last line of `winid`'s buffer, retrying on the next
---scheduled tick if the window isn't valid yet (e.g. right after creation).
---@param winid integer
---@param retries? integer Remaining retry attempts (internal use)
function M.ensure_bottom(winid, retries)
  retries = retries or 3
  if not vim.api.nvim_win_is_valid(winid) then
    if retries > 0 then
      vim.schedule(function()
        M.ensure_bottom(winid, retries - 1)
      end)
    end
    return
  end
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local last_line = vim.api.nvim_buf_line_count(bufnr)
  pcall(vim.api.nvim_win_set_cursor, winid, { last_line, 0 })
end

---Make a window focusable if it was created with `focusable = false`.
---@param winid integer
---@return boolean ok
function M.make_focusable(winid)
  if not vim.api.nvim_win_is_valid(winid) then
    return false
  end
  local ok, cfg = pcall(vim.api.nvim_win_get_config, winid)
  if not ok or cfg.relative == "" then
    return false -- not a floating window; focusability isn't configurable here
  end
  cfg.focusable = true
  local ok_set = pcall(vim.api.nvim_win_set_config, winid, cfg)
  return ok_set
end

---Force focus onto `winid`, making it focusable first if needed.
---@param winid integer
---@return boolean ok
function M.force_focus(winid)
  if not vim.api.nvim_win_is_valid(winid) then
    return false
  end
  M.make_focusable(winid)
  local ok = pcall(vim.api.nvim_set_current_win, winid)
  return ok
end

---Force focus onto `winid` and scroll it to the bottom.
---@param winid integer
---@return boolean ok
function M.focus_and_bottom(winid)
  local ok = M.force_focus(winid)
  if ok then
    M.ensure_bottom(winid)
  end
  return ok
end

return M
