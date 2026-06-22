---@module 'lib.nvim.buffer.get_alternate'

--- AUDIT: Implementiere in lib

--- Get the alternate buffer (like :e #)
---@return integer|nil bufnr Buffer number of alternate buffer
---@return string|nil filepath Full path of the alternate buffer
return function ()
  -- vim.fn.bufnr('#') gibt die alternate buffer number zurück
  local alt_bufnr = vim.fn.bufnr('#')

  -- Prüfen ob gültig
  if alt_bufnr == -1 or not vim.api.nvim_buf_is_valid(alt_bufnr) then
    return nil, nil
  end

  -- Dateiname holen
  local filepath = vim.api.nvim_buf_get_name(alt_bufnr)
  if filepath == "" then
    return nil, nil
  end

  -- Prüfen ob es ein echter File-Buffer ist (nicht special buffer)
  local buftype = vim.bo[alt_bufnr].buftype
  if buftype ~= "" then
    return nil, nil
  end

  return alt_bufnr, filepath
end

