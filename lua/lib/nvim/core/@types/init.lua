---@meta
---@module 'lib.nvim.@types'

---@class Lib.Nvim
---@field has_exec fun(bin: string): boolean # Memoized `vim.fn.executable(bin) == 1` check.
---@field first_available fun(candidates: string[]): string|nil # First candidate binary found on PATH (via has_exec), or nil if none are.
---@field simple_echo fun(msg: string, hl: string|nil, is_error: boolean|nil): integer|string # This module returns a single function that echoes messages using vim.api.nvim_echo

return {}

---@class EchoChunk
---@field [1] string text of the message
---@field [2]? string highlight group name (optional)
