# `lib.nvim.buf_win_tab.word_under_cursor`

Extract the word under the cursor using a configurable word-character pattern,
and report its byte span.

`vim.fn.expand("<cword>")` can do neither: it is bound to `iskeyword` and
returns only the text with no position. Callers that need to **replace** the
word (via `nvim_buf_set_text`), or to treat characters like apostrophes as part
of a word (`don't`), otherwise have to hand-roll this.

Columns are 0-based (matching `nvim_win_get_cursor` and `nvim_buf_set_text`);
`end_col` is exclusive. `row` is 1-based.

## Usage

```lua
local word_under_cursor = require("lib.nvim.buf_win_tab.word_under_cursor")

-- Default pattern "[%w_']" keeps apostrophes: cursor inside "don't" -> "don't"
local w = word_under_cursor()
if w then
  vim.print(w.word) --> "don't"

  -- Replace it in place:
  vim.api.nvim_buf_set_text(0, w.row - 1, w.start_col, w.row - 1, w.end_col, { "do not" })
end

-- Custom pattern: include dots, so "foo.bar.baz" is one word
local dotted = word_under_cursor({ pattern = "[%w_%.]" })
```

## Returns

| Field       | Type      | Meaning                            |
|-------------|-----------|------------------------------------|
| `word`      | `string`  | The matched word                   |
| `start_col` | `integer` | 0-based inclusive start column     |
| `end_col`   | `integer` | 0-based exclusive end column       |
| `row`       | `integer` | 1-based row                        |

Returns `nil` when the cursor is not on a character matching `pattern`.
