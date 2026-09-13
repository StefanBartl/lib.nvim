# `lib.vim.usercmd`

Classic-Vim mirror of [`lib.nvim.usercmd`](../../nvim/usercmd/README.md). **Status: stub, not yet
ported** — see [`doc/vim-parity.md`](../../../../doc/vim-parity.md) for the full table across
every `lib.vim.*` module.

Every function name on this module resolves (built on [`lib.vim._stub`](../_stub.lua)), but
calling one raises:

```
lib.vim.usercmd.<fn>: not yet implemented for classic Vim. Under Neovim, use lib.nvim.usercmd instead.
```

This lets dependent code already program against `lib.vim.usercmd` while a real port lands later.
Porting note for this module: `:command!`.
