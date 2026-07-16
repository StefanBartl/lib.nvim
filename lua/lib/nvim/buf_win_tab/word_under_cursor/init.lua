---@module 'lib.nvim.buf_win_tab.word_under_cursor'
--- Extract the word under the cursor using a configurable word-character
--- pattern, and report its byte span.
---
--- `vim.fn.expand("<cword>")` can do neither: it is bound to `iskeyword` and
--- returns only the text, no position — so callers that need to *replace* the
--- word (via `nvim_buf_set_text`) or to treat e.g. apostrophes as part of a
--- word ("don't") have to hand-roll this. Hence this helper.
---
--- Columns are 0-based (matching `nvim_win_get_cursor` and
--- `nvim_buf_set_text`); `end_col` is exclusive.

require("lib.nvim.buf_win_tab.word_under_cursor.@types")

---@param opts? Lib.BufWinTab.WordUnderCursorOpts
---@return Lib.BufWinTab.WordUnderCursor|nil # `nil` when the cursor is not on a word character
return function(opts)
  opts = opts or {}
  local pattern = opts.pattern or "[%w_']"

  local ok_cur, cursor = pcall(vim.api.nvim_win_get_cursor, 0)
  if not ok_cur then
    return nil
  end
  local row, col = cursor[1], cursor[2] -- row 1-based, col 0-based

  local lines = vim.api.nvim_buf_get_lines(0, row - 1, row, false)
  local line = lines[1]
  if not line or line == "" then
    return nil
  end

  -- Convert to a 1-based index for string.sub.
  local idx = col + 1
  if idx > #line then
    return nil
  end
  if not line:sub(idx, idx):match(pattern) then
    return nil
  end

  local start_idx = idx
  while start_idx > 1 and line:sub(start_idx - 1, start_idx - 1):match(pattern) do
    start_idx = start_idx - 1
  end

  local end_idx = idx
  while end_idx < #line and line:sub(end_idx + 1, end_idx + 1):match(pattern) do
    end_idx = end_idx + 1
  end

  return {
    word = line:sub(start_idx, end_idx),
    start_col = start_idx - 1, -- back to 0-based
    end_col = end_idx, -- exclusive in 0-based terms
    row = row,
  }
end
