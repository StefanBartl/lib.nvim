# `lib.vim.lua_ls`

Classic-Vim mirror of `lib.nvim.lua_ls`. **Status: stub, not yet
ported** — see [`doc/vim-parity.md`](../../../../doc/vim-parity.md) for the full table across
every `lib.vim.*` module.

Every function name on this module resolves (built on [`lib.vim._stub`](../_stub.lua)), but
calling one raises:

```
lib.vim.lua_ls.<fn>: not yet implemented for classic Vim. Under Neovim, use lib.nvim.lua_ls instead.
```

This lets dependent code already program against `lib.vim.lua_ls` while a real port lands later.
Porting note for this module: pure path/string handling, ports well.
