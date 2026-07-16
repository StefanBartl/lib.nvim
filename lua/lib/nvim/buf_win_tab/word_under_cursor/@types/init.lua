---@meta
---@module 'lib.nvim.buf_win_tab.word_under_cursor.@types'

---@class Lib.BufWinTab.WordUnderCursorOpts
---@field pattern? string Lua character class matched per byte (default `"[%w_']"`)

---The word under the cursor and its byte span.
---Columns are 0-based (matching `nvim_win_get_cursor`/`nvim_buf_set_text`);
---`end_col` is exclusive. `row` is 1-based.
---@class Lib.BufWinTab.WordUnderCursor
---@field word string
---@field start_col integer 0-based inclusive
---@field end_col integer 0-based exclusive
---@field row integer 1-based

---@alias Lib.BufWinTab.WordUnderCursorFn fun(opts?: Lib.BufWinTab.WordUnderCursorOpts): Lib.BufWinTab.WordUnderCursor|nil
