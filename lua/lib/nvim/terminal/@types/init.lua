---@meta
---@module 'lib.nvim.terminal.@types'

---@class Lib.Terminal
---@field escape fun(path: string): string # Cross-platform path escaping for terminal commands (escapes spaces and special characters for shell)
---@field is_terminal_buf fun(bufnr: integer): boolean|nil # Checks if buffer is a terminal buffer; returns true if, else false
---@field delete_terminal_buf fun(bufnr: integer): boolean|nil # Force-deletes `bufnr` regardless of buftype; returns nil if `bufnr` isn't a number, else whether the delete succeeded
---@field is_kitty fun(): boolean # Return true if the current terminal environment is Kitty (Linux/macOS). Heuristics: KITTY_LISTEN_ON set OR TERM contains "kitty".

return {}
