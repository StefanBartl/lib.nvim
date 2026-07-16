# `lib.nvim.dotrepeat`

Native `.`-repeat wiring through Vim's `operatorfunc` mechanism — no
dependency on `vim-repeat` or any other plugin.

Vim's dot-repeat re-invokes whatever `operatorfunc` currently names, not the
mapping that first triggered it. `M.run(fn)` stores `fn` as a module-local
"pending" callback, points `operatorfunc` at one stable dispatcher
(`M._invoke`, reached from Vimscript via `v:lua`), and fires the operator
machinery once with a single-character pseudo-motion (`g@l`). Because the
dispatcher always re-reads the pending fn, pressing `.` later calls
`M._invoke` again, which re-invokes the same `fn`.

## Usage

```lua
local dotrepeat = require("lib.nvim.dotrepeat")

local function insert_snippet()
  vim.api.nvim_put({ "-- snippet" }, "l", true, true)
end

vim.keymap.set("n", "<leader>x", function()
  dotrepeat.run(insert_snippet)
end)
-- <leader>x inserts once; pressing `.` afterwards inserts it again.
```

Or wrap once and reuse the wrapped function directly as the keymap callback:

```lua
local repeatable_insert = dotrepeat.repeatable(insert_snippet)
vim.keymap.set("n", "<leader>x", repeatable_insert)
```

## Returns

`M.run` and `M.repeatable` have no return value worth documenting beyond
their signatures above — see `lua/lib/nvim/dotrepeat/@types/init.lua`.
