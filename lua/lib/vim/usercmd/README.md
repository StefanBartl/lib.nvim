# `lib.vim.usercmd`

Classic-Vim mirror of [`lib.nvim.bindings.usercmd`](../../nvim/bindings/usercmd/README.md) (the
former `lib.nvim.usercmd` this mirror was originally written against was removed on 2026-09-18).
**Status: stub, not yet
ported** — see [`doc/vim-parity.md`](../../../../doc/vim-parity.md) for the full table across
every `lib.vim.*` module.

Every function name on this module resolves (built on [`lib.vim._stub`](../_stub.lua)), but
calling one raises:

```
lib.vim.usercmd.<fn>: not yet implemented for classic Vim. Under Neovim, use lib.nvim.usercmd instead.
```

The stub's error text still says `lib.nvim.usercmd` (the module name it was built with, now
stale) rather than `lib.nvim.bindings.usercmd` — a separate follow-up in `lib.vim._stub`'s own
generic mirroring, not fixed here.

This lets dependent code already program against `lib.vim.usercmd` while a real port lands later.
Porting note for this module: `:command!`.
