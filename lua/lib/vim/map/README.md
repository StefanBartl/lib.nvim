# `lib.vim.map`

Classic-Vim mirror of [`lib.nvim.bindings.keymap`](../../nvim/bindings/keymap/README.md) (the
former `lib.nvim.map` this mirror was originally written against was removed on 2026-09-18; the
bindings equivalent was also renamed `map` -> `keymap`). **Status: stub, not yet
ported** — see [`doc/vim-parity.md`](../../../../doc/vim-parity.md) for the full table across
every `lib.vim.*` module.

Every function name on this module resolves (built on [`lib.vim._stub`](../_stub.lua)), but
calling one raises:

```
lib.vim.map.<fn>: not yet implemented for classic Vim. Under Neovim, use lib.nvim.map instead.
```

The stub's error text still says `lib.nvim.map` (the module name it was built with, now stale)
rather than `lib.nvim.bindings.keymap` — a separate follow-up in `lib.vim._stub`'s own generic
mirroring, not fixed here.

This lets dependent code already program against `lib.vim.map` while a real port lands later.
Porting note for this module: `:map`/`mapset()`.
