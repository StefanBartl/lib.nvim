---@meta
---@module 'lib.nvim.terminal.@types'

---@class Lib.Terminal
---@field escape fun(path: string): string # Cross-platform path escaping for terminal commands (escapes spaces and special characters for shell)
---@field is_terminal_buf fun(bufnr: integer): boolean|nil # Checks if buffer is a terminal buffer; returns true if, else false
---@field delete_terminal_buf fun(bufnr: integer): boolean|nil # Force-deletes `bufnr` regardless of buftype; returns nil if `bufnr` isn't a number, else whether the delete succeeded
---@field is_kitty fun(): boolean # Return true if the current terminal environment is Kitty (Linux/macOS). Heuristics: KITTY_LISTEN_ON set OR TERM contains "kitty".
---@field spawn fun(opts: Lib.Terminal.SpawnOpts): Lib.Terminal.Spawned|nil, string|nil # Start an argv in a terminal float or split; nil + message when the window or the job could not be created (no window is left behind)

---@class Lib.Terminal.SpawnOpts
---@field argv string|string[] # program and arguments (no shell parsing)
---@field cwd? string
---@field layout? "float"|"split"|"vsplit" # default "float"
---@field title? string # float only
---@field border? string # float only, default "rounded"
---@field ratio? number # float only, share of the editor, default 0.9
---@field size? integer # split height
---@field close_on_exit? "always"|"ok"|"never" # default "never"
---@field startinsert? boolean # default true
---@field on_open? fun(bufnr: integer, winid: integer, job: integer) # after the job started (terminal-mode keymaps)
---@field on_exit? fun(code: integer, bufnr: integer) # scheduled, after the optional close

---@class Lib.Terminal.Spawned
---@field bufnr integer
---@field winid integer
---@field job integer

return {}
