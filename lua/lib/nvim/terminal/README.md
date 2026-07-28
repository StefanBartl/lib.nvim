# `lib.nvim.terminal`

Small terminal-buffer helpers: shell-escaping, terminal-buffer detection and
cleanup, and a Kitty-terminal check.

## Usage

```lua
local terminal = require("lib.nvim.terminal")

terminal.escape("my file.txt")   --> "my\\ file.txt"
```

`escape(path)` backslash-escapes spaces and `` $`\ `` for shell use — a
narrow, ad-hoc set of characters, not a full shell-quoting implementation.

```lua
terminal.is_terminal_buf(bufnr)          --> true / false / nil
```

Returns `true`/`false` based on `vim.bo[bufnr].buftype == "terminal"`. The
`nil` branch guards against `buftype` itself coming back falsy (`nil` or
`false`); in practice `vim.bo[bufnr].buftype` is always a string for a valid
buffer and indexing `vim.bo` with an invalid buffer number raises rather than
returning a falsy value, so callers should still validate `bufnr` themselves
(e.g. via `lib.nvim.normalize.buf_valid`) before calling this.

```lua
terminal.delete_terminal_buf(bufnr)      --> true / false / nil
```

Returns `nil` immediately if `bufnr` isn't a number; otherwise attempts
`vim.api.nvim_buf_delete(bufnr, { force = true })` inside `pcall` and returns
whether that succeeded. Note: unlike its doc comment implies, it does **not**
check `is_terminal_buf` first — it force-deletes whatever buffer number it's
given.

```lua
terminal.is_kitty()   --> boolean
```

True if `$KITTY_LISTEN_ON` is set and non-empty, or if `$TERM` contains
`"kitty"`.
