---@module 'lib.nvim.terminal'
--- Terminal helper functions: path escaping, terminal-buffer detection/cleanup,
--- and Kitty-terminal detection.

require("lib.nvim.terminal.@types")

local M = {}

-- Cross-platform path escaping for terminal commands
-- Escape spaces and special characters for shell
---@param path string
---@return string
function M.escape(path)
  return (path:gsub("([%s%$`\\])", "\\%1"))
end

--- Checks if buffer is a terminal buffer.
--- Returns `nil` when `bufnr`'s `buftype` cannot be read.
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

--- Deletes `bufnr` if it is a valid buffer number (force-deletes without
--- checking `buftype`). Returns `nil` when `bufnr` is not a number.
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

--- Return true if the current terminal environment is Kitty (Linux/macOS).
--- Heuristics: `KITTY_LISTEN_ON` set, or `TERM` contains "kitty".
---@return boolean
function M.is_kitty()
  local env = vim.env
  if env.KITTY_LISTEN_ON and env.KITTY_LISTEN_ON ~= "" then
    return true
  end
  local term = env.TERM or ""
  return term:find("kitty", 1, true) ~= nil
end

---@type Lib.Terminal.ALL
return M
