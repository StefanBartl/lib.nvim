# `lib.vim.window`

Classic-Vim mirror of [`lib.nvim.window`](../../nvim/window/README.md). **Status: stub, not yet
ported** — see [`doc/vim-parity.md`](../../../../doc/vim-parity.md) for the full table across
every `lib.vim.*` module.

Every function name on this module resolves (built on [`lib.vim._stub`](../_stub.lua)), but
calling one raises:

```
lib.vim.window.<fn>: not yet implemented for classic Vim. Under Neovim, use lib.nvim.window instead.
```

This lets dependent code already program against `lib.vim.window` while a real port lands later.
Porting note for this module: `win_*()`.
