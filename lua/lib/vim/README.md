# `lib.vim`

Namespace aggregator for the classic-Vim mirror of `lib.nvim.*`.

```lua
local Vim = require("lib.vim")
Vim.notify    -- == require("lib.vim.notify")
```

For every `lib.nvim.<module>`, the goal is an API-compatible `lib.vim.<module>`
that works under classic Vim (`vim.fn`/Vimscript only, no `vim.api`/`vim.uv`).
Where a port is feasible, the module is a real implementation; where it is
not (yet), it is a stub built from [`_stub`](_stub.lua): every function name
on the module resolves, but calling one raises a clear
`lib.vim.<module>.<fn>: not yet implemented for classic Vim. Under Neovim,
use lib.nvim.<module> instead.` This lets dependent code already program
against `lib.vim.*` while real implementations land over time.

Porting status for every module: [`doc/vim-parity.md`](../../../doc/vim-parity.md).
