---@meta
---@module 'lib.nvim.@types'

---@class Lib.Nvim
---@field has_exec fun(bin: string): boolean
---@field simple_echo fun(msg: string, hl: string|nil, is_error: boolean|nil): integer|string # This module returns a single function that echoes messages using vim.api.nvim_echo

return {}

---@class EchoChunk
---@field [1] string text of the message
---@field [2]? string highlight group name (optional)
