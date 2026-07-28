# `lib.nvim.map`

Convenience wrapper around `vim.keymap.set` — applies sane defaults and
validates arguments defensively, reporting bad calls with the actual call
site instead of a raw `vim.keymap.set` traceback.

The module *is* a function (`return function(modes, lhs, rhs, opts, desc)
... end`), not a table — call `require("lib.nvim.map")` directly.

## Usage

```lua
local map = require("lib.nvim.map")

map("n", "<leader>ff", ":Telescope find_files<CR>", nil, "Find files")
map({ "n", "v" }, "<leader>y", '"+y', { silent = false })
map("n", "<leader>x", my_fn, { buffer = true })   -- buffer = true -> current buffer (0)
map("n", "<leader>x", my_fn, { buffer = 12 })     -- explicit bufnr
```

Defaults applied when not set explicitly: `opts.noremap = true`,
`opts.silent = true`, `opts.desc = ""`. The trailing `desc` positional
argument, when a string, overrides `opts.desc`. `opts.buffer = true` is
normalized to `0` (current buffer) before being handed to
`vim.keymap.set`.

## Argument validation

Before calling `vim.keymap.set`, each argument is checked:

| Arg | Must be |
| --- | --- |
| `modes` | `string` or `table` |
| `lhs` | `string` |
| `rhs` | `function` or `string` |
| `opts.buffer` | `nil`, `boolean`, or `number` |

On any failure, `vim.keymap.set` is **not** called — instead
`require("lib.nvim.notify")` (tagged `[lib.nvim.map]`) reports every failing
field at once, along with the actual call site resolved via
`debug.getinfo(4, ...)` (four stack frames up: past this validator, past the
wrapper itself, to the real caller).
