---@module 'lib.nvim.window.tag'
--- Identify windows by an arbitrary string tag stored in `vim.w[win].custom_tag`
--- — the same convention `lib.nvim.buf_win_tab.capture` uses for its `tag`
--- option. Lets a caller find "the window I tagged earlier" by scanning live
--- windows instead of keeping its own registry, which can go stale when a
--- window closes through a path the registry never observed.

local api = vim.api

local M = {}

---Tag `win` (and optionally its buffer) for later lookup via `M.find`.
---@param win integer
---@param tag string
---@param buf? integer
function M.set(win, tag, buf)
  vim.w[win].custom_tag = tag
  if buf ~= nil then
    vim.b[buf].custom_tag = tag
  end
end

---Read the tag previously applied to `win`, if any.
---@param win integer
---@return string|nil
function M.get(win)
  if not api.nvim_win_is_valid(win) then
    return nil
  end
  return vim.w[win] and vim.w[win].custom_tag or nil
end

---Find a live, real content window (not a hidden/degenerate float) tagged
---`tag`. Returns the first match across all tabpages.
---@param tag string
---@return integer|nil
function M.find(tag)
  for _, win in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_is_valid(win) then
      local win_tag = vim.w[win] and vim.w[win].custom_tag or nil
      if win_tag == tag then
        local ok, config = pcall(api.nvim_win_get_config, win)
        if ok and config.relative ~= "win" and config.width > 1 and config.height > 1 then
          return win
        end
      end
    end
  end
  return nil
end

return M
