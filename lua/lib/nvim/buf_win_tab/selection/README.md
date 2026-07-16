# `lib.nvim.buf_win_tab.selection`

Read the visual selection, whether or not visual mode is still active.

While visual mode is active the selection is bounded by the `v` mark and the
cursor; once it has ended it is bounded by the `'<` / `'>` marks. `get_visual_selection`
handles both cases, so a mapping behaves identically whether it fires from a
visual-mode `:` command (which leaves visual mode before running) or from a
`vim.keymap.set("v", ...)` callback (which does not).

Rows are 1-based (Vim convention); columns are 1-based and **inclusive on both
ends**, matching `string.sub` so slices can be taken directly. Selections made
with the cursor *before* the anchor are normalized, and the linewise-mode
end column is clamped to the real line length.

## Usage

```lua
local selection = require("lib.nvim.buf_win_tab.selection")

vim.keymap.set("v", "<leader>u", function()
  local sel = selection.get_visual_selection()
  if not sel then return end

  -- Uppercase the selection in place.
  local upper = vim.tbl_map(string.upper, sel.lines)
  vim.api.nvim_buf_set_text(
    0, sel.start_row - 1, sel.start_col - 1, sel.end_row - 1, sel.end_col, upper
  )
end)

selection.reselect_visual() -- programmatic `gv`
```

## `get_visual_selection` returns

| Field       | Type       | Meaning                                  |
|-------------|------------|------------------------------------------|
| `lines`     | `string[]` | Selected text, already sliced by column  |
| `start_row` | `integer`  | 1-based first row                        |
| `start_col` | `integer`  | 1-based inclusive first column           |
| `end_row`   | `integer`  | 1-based last row                         |
| `end_col`   | `integer`  | 1-based inclusive last column            |

Returns `nil` when no usable selection exists (marks unset, empty range).
