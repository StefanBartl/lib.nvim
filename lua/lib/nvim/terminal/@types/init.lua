---@meta
---@module 'lib.nvim.terminal.@types'

---@class Lib.Terminal
---@field escape fun(path: string): string # Cross-platform path escaping for terminal commands
-- Escape spaces and special characters for shell
---@field is_terminal_buf fun(bufnr: integer): boolean|nil # Checks if buffer is a terminal buffer; returns true if, else false
---@field delete_terminal_buf fun(bufnr: integer): boolean|nil # Checks if buffer is terminal buffer, if -> try to delete terminal buffer and return boolean of succes, else return nil

---@class Lib.Terminal.ALL
---@field escape fun(path: string): string # Cross-platform path escaping for terminal commands
-- Escape spaces and special characters for shell
---@field is_terminal_buf fun(bufnr: integer): boolean|nil # Checks if buffer is a terminal buffer; returns true if, else false
---@field delete_terminal_buf fun(bufnr: integer): boolean|nil # Checks if buffer is terminal buffer, if -> try to delete terminal buffer and return boolean of succes, else return nil
---@field is_kitty fun(): nil # Return true if the current terminal environment is Kitty (Linux/macOS). Heuristics: KITTY_LISTEN_ON set OR TERM contains "kitty". Return true if the current terminal environment is Kitty (Linux/macOS). Heuristics: KITTY_LISTEN_ON set OR TERM contains "kitty".

return {}
