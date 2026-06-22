---@module 'lib.nvim.buf_win_tab.save_adjacent_buffer'
---Helper to force-save the last usable file buffer via :w!

local M = {}

---Checks whether a buffer is a normal, writable file buffer
---@param bufnr integer
---@return boolean
local function is_normal_file_buffer(bufnr)
  -- Buffer must exist
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  -- Must be listed (skip hidden/internal buffers)
  if not vim.bo[bufnr].buflisted then
    return false
  end

  -- Skip special buffers (neo-tree, netrw, help, terminal, prompt, etc.)
  if vim.bo[bufnr].buftype ~= "" then
    return false
  end

  -- Must have a file name
  if vim.api.nvim_buf_get_name(bufnr) == "" then
    return false
  end

  return true
end

---Force-save the last relevant file buffer using :w!
---Never saves the current (neo-tree) buffer.
function M.save_last_normal_buffer()
  -- 1. Prefer alternate buffer (#)
  local alt = vim.fn.bufnr("#")
  if is_normal_file_buffer(alt) then
    vim.api.nvim_buf_call(alt, function()
      vim.cmd("w!")
    end)
    return
  end

  -- 2. Fallback: iterate buffers by last-used order
  ---@type integer[]
  local buffers = vim.api.nvim_list_bufs()

  -- Iterate in reverse order: most recently used first
  for i = #buffers, 1, -1 do
    local bufnr = buffers[i]
    if is_normal_file_buffer(bufnr) then
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd("w!")
      end)
      return
    end
  end

  -- 3. No suitable buffer found → do nothing silently
end

---@type Lib.BufWinTab.SafeAdjacentBuffer
return M

