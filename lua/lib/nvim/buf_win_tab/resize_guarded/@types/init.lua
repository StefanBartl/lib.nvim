---@meta
---@module 'lib.nvim.buf_win_tab.resize_guarded.@types'

--- Guarded resize helper that allows window resize shortcuts in normal editors
--- while preserving keypresses in terminals and special plugin buffers: a
--- terminal-mode mapping that early-returns still consumes the keypress, so
--- excluded buffers get the original key forwarded via `nvim_feedkeys`
--- instead of running the resize command. See `resize_guarded/init.lua` for
--- usage and the exclusion/forwarding implementation.
---@class Lib.BufWinTab.ResizeGuarded
---@field create fun(cmd: string, exclude_filetypes?: string[], exclude_names?: string[], lhs?: string): function # Create guarded resize mapping callback function. Returns callback suitable for vim.keymap.set. Arguments: cmd (resize command like "vertical resize -5"), exclude_filetypes (list of filetypes to exclude), exclude_names (list of Lua patterns matching buffer names to exclude), lhs (original mapping lhs like "<S-h>" - REQUIRED for key forwarding). Behavior: checks current buffer against exclusions, either forwards key or executes resize. Warns if lhs provided but fallback derivation fails.

---@alias ResizeCallback fun(): nil
--- Callback returned by create(): checks the current buffer against the
--- exclusion lists and either forwards the original key or runs the resize
--- command via `vim.cmd`, reporting a failure through `notify.error`.

return {}
