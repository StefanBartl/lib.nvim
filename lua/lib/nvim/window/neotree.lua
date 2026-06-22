---@module 'lib.nvim.window.neotree'
---Utility functions related to the Neo-tree window.

-- AUDIT: In `lib` implementieren

local M = {}

---@return integer|false
---Returns the window ID of the currently open Neo-tree window.
---If no Neo-tree window exists, false is returned.
function M.get_neotree_window()
  -- Iterate over all existing windows in the current Neovim instance
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    -- Get the buffer associated with the window
    local buf = vim.api.nvim_win_get_buf(win)

    -- Check whether the buffer is valid to avoid API errors
    if vim.api.nvim_buf_is_valid(buf) then
      -- Read the 'filetype' option of the buffer
      local filetype = vim.api.nvim_buf_get_option(buf, "filetype")

      -- Neo-tree buffers always use the 'neo-tree' filetype
      if filetype == "neo-tree" then
        return win
      end
    end
  end

  -- Explicitly return false if no Neo-tree window was found
  return false
end

return M

