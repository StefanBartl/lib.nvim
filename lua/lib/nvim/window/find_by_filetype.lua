---@module 'lib.nvim.window.find_by_filetype'
---Find the first open window whose buffer has a given `filetype`.
---
---Generic replacement for filetree-manager-specific window lookups (Neo-tree's
---`"neo-tree"`, nvim-tree's `"NvimTree"`, etc.) — callers pass the filetype
---they care about instead of the helper hardcoding one.

local M = {}

---@param filetype string Buffer `filetype` to search for (e.g. `"neo-tree"`, `"NvimTree"`)
---@return integer|false winid Window id of the first match, or `false` if none exists
function M.find_by_filetype(filetype)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_buf_is_valid(buf) then
      local ok, ft = pcall(vim.api.nvim_get_option_value, "filetype", { buf = buf })
      if ok and ft == filetype then
        return win
      end
    end
  end
  return false
end

return M
