---@meta
---@module 'lib.nvim.buf_win_tab.normal_buffer.@types'

---Shared primitives around "normal" file buffers.
---@class Lib.BufWinTab.NormalBuffer
---@field is_normal_file_buffer fun(bufnr?: integer): boolean
---@field find_last_normal_window fun(exclude_win?: integer): (integer|nil, integer|nil)
---@field edit_in_window fun(winid: integer, path: string): (boolean, string|nil)
---@field prompt_save fun(bufnr: integer): boolean

return {}
