---@module 'lib.nvim.buffer.is_markdown_buf'
--- Returns the current buffer number if the buffer is a valid loaded markdown buffer.
--- Usage: local bufnr = require("lib.nvim.buffer.is_markdown_buf")()

---@param bufnr_arg integer|nil Optional buffer number to check; if nil the current buffer is used.
---@return integer|nil buffer number if the buffer is a markdown buffer and valid, otherwise nil
return function(bufnr_arg)
  local bufnr = bufnr_arg or vim.api.nvim_get_current_buf()
  if not (vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_is_valid(bufnr)) then
    return nil
  end
  -- Use buffer-local filetype check
  if vim.bo[bufnr].filetype == "markdown" then
    return bufnr
  end
  return nil
end
