# `lib.nvim.safe_api`

Validated, `pcall`-wrapped `vim.api` accessors for buffers/windows. Every
call validates its handle (and other arguments) up front, then routes the
actual `vim.api` call through `pcall`, so a deleted buffer or a closed
window never raises past a UI callback (extmark highlighting, async job
completion, autocmd handlers) — it just returns `false` plus an error
string.

## Usage

```lua
local safe_api = require("lib.nvim.safe_api")

local ok, lines, err = safe_api.buf_get_lines(bufnr, 0, -1, false)
if not ok then
  return
end
```

## Return shape

Every function shares one shape: `success: boolean, result: any|nil,
error: string|nil`.

`is_valid_buffer`/`is_valid_window` skip the `pcall` for hot paths that
only need a boolean.

## Functions

- `safe_call(fn, ...)` — generic `pcall` wrapper, normalized to `(ok, result, err)`.
- `is_valid_buffer(bufnr)` / `is_valid_window(winnr)` — fast boolean checks.
- `buf_get_lines(bufnr, start, end_, strict_indexing)`
- `buf_line_count(bufnr)`
- `buf_get_option(bufnr, name)` / `buf_set_option(bufnr, name, value)`
- `buf_set_extmark(bufnr, ns_id, line, col, opts)`
- `set_extmark(bufnr, ns_id, line, col_start, col_end, hl_group, line_content, priority?)` —
  convenience wrapper that clamps/validates `col_start`/`col_end` against
  `line_content`'s length first, so callers highlighting many ranges per
  line don't need to re-fetch/re-validate it themselves.
- `buf_clear_namespace(bufnr, ns_id, line_start, line_end)`
- `win_get_option(winnr, name)` / `win_set_option(winnr, name, value)`
- `win_get_buf(winnr)` / `win_close(winnr, force)`
- `buf_delete(bufnr, opts?)`
- `with_retry(fn, max_retries, ...)` — retries `fn` when the failure looks
  handle-related (an `"invalid"`/`"closed"` error), gives up immediately on
  any other kind of error.
