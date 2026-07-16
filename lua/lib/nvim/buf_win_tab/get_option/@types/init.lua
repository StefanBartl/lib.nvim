---@meta
---@module 'lib.nvim.buf_win_tab.get_option.@types'

---Read a buffer option, trying every API route across Neovim versions.
---Returns `nil` when all routes fail.
---@alias Lib.BufWinTab.GetOption fun(bufnr: integer, name: string): any|nil
