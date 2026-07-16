---@module 'lib.nvim.window.find_usable'
--- Find a "normal" window to display content in — not a floating window,
--- not a sidebar-like window (fixed width/height, or a well-known sidebar
--- filetype). Useful for plugins that want to reuse an existing normal
--- split instead of always opening a new one.

local M = {}

local SIDEBAR_FILETYPES = {
  ["neo-tree"] = true,
  ["NvimTree"] = true,
  ["aerial"] = true,
  ["Outline"] = true,
  ["qf"] = true,
}

---True when `winid` is a normal, non-floating, non-sidebar window.
---@param winid integer
---@return boolean
function M.is_usable_window(winid)
  if not vim.api.nvim_win_is_valid(winid) then
    return false
  end
  local ok_cfg, cfg = pcall(vim.api.nvim_win_get_config, winid)
  if ok_cfg and cfg.relative ~= "" then
    return false -- floating window
  end
  local ok_buf, bufnr = pcall(vim.api.nvim_win_get_buf, winid)
  if not ok_buf then
    return false
  end
  local ok_ft, ft = pcall(vim.api.nvim_get_option_value, "filetype", { buf = bufnr })
  if ok_ft and SIDEBAR_FILETYPES[ft] then
    return false
  end
  return true
end

---Find the first usable normal window, preferring the current one.
---@param opts? { current_tab_only?: boolean }
---@return integer|nil winid
function M.target_window(opts)
  opts = opts or {}
  local cur = vim.api.nvim_get_current_win()
  if M.is_usable_window(cur) then
    return cur
  end
  local wins = opts.current_tab_only and vim.api.nvim_tabpage_list_wins(0) or vim.api.nvim_list_wins()
  for _, winid in ipairs(wins) do
    if M.is_usable_window(winid) then
      return winid
    end
  end
  return nil
end

return M
