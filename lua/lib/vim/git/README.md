# `lib.vim.git`

Classic-Vim mirror of [`lib.nvim.git`](../../nvim/git/README.md). **Status: stub, not yet
ported** — see [`doc/vim-parity.md`](../../../../doc/vim-parity.md) for the full table across
every `lib.vim.*` module.

Every function name on this module resolves (built on [`lib.vim._stub`](../_stub.lua)), but
calling one raises:

```
lib.vim.git.<fn>: not yet implemented for classic Vim. Under Neovim, use lib.nvim.git instead.
```

This lets dependent code already program against `lib.vim.git` while a real port lands later.
Porting note for this module: `system()`.
