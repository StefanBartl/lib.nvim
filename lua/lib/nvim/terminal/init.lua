---@module 'lib.nvim.terminal'
-- Terminal helper functions

local M = {}

-- Cross-platform path escaping for terminal commands
-- Escape spaces and special characters for shell
---@param path string
---@return string
function M.escape(path)
  return (path:gsub("([%s%$`\\])", "\\%1"))
end

--- Checks if buffer is a terminal buffer
---@param bufnr integer
---@return boolean|nil
function M.is_terminal_buf(bufnr)
  local buftype = vim.bo[bufnr].buftype
  if not buftype then
    return nil
  end

  if buftype == "terminal" then
    return true
  else
    return false
  end
end

--- Checks if buffer is terminal buffer, if -> try to delete terminal buffer and return boolean of succes, else return nil
---@param bufnr integer
---@return boolean|nil
function M.delete_terminal_buf(bufnr)
  if not bufnr or type(bufnr) ~= "number" then
    return nil
  end
  local ok, _ = pcall(function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
  if ok then
    return true
  else
    return false
  end
end

---@return boolean
function M.is_kitty()
  local env = vim.env
  if env.KITTY_LISTEN_ON and env.KITTY_LISTEN_ON ~= "" then
    return true
  end
  local term = env.TERM or ""
  return term:find("kitty", 1, true) ~= nil
end

return M
