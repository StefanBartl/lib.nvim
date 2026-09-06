---@module 'lib.nvim.buffer.get_alternate'

--- Get the alternate buffer (like :e #)
---@return integer|nil bufnr Buffer number of alternate buffer
---@return string|nil filepath Full path of the alternate buffer
return function()
  -- `bufnr('#')` is the alternate buffer, or -1 when there is none.
  local alt_bufnr = vim.fn.bufnr("#")

  if alt_bufnr == -1 or not vim.api.nvim_buf_is_valid(alt_bufnr) then
    return nil, nil
  end

  local filepath = vim.api.nvim_buf_get_name(alt_bufnr)
  if filepath == "" then
    return nil, nil
  end

  -- A file-backed buffer only: a terminal, help or quickfix buffer has a name
  -- but no path a caller could open.
  local buftype = vim.bo[alt_bufnr].buftype
  if buftype ~= "" then
    return nil, nil
  end

  return alt_bufnr, filepath
end
