# `lib.vim.autocmd`

Classic-Vim mirror of [`lib.nvim.bindings.autocmd`](../../nvim/bindings/autocmd/README.md) (the
former `lib.nvim.autocmd` this mirror was originally written against was removed on 2026-09-18).
**Status: stub, not yet
ported** — see [`doc/vim-parity.md`](../../../../doc/vim-parity.md) for the full table across
every `lib.vim.*` module.

Every function name on this module resolves (built on [`lib.vim._stub`](../_stub.lua)), but
calling one raises:

```
lib.vim.autocmd.<fn>: not yet implemented for classic Vim. Under Neovim, use lib.nvim.autocmd instead.
```

The stub's error text still says `lib.nvim.autocmd` (the module name it was built with, now
stale) rather than `lib.nvim.bindings.autocmd` — a separate follow-up in `lib.vim._stub`'s own
generic mirroring, not fixed here.

This lets dependent code already program against `lib.vim.autocmd` while a real port lands later.
Porting note for this module: `:autocmd`/`:augroup`.
