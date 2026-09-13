# `lib.vim` — porting status (Vim parity)

Goal: for every module in `lib.nvim.*`, an API-compatible counterpart in
`lib.vim.*` that works under **classic Vim** (without the Neovim
`vim.api`/`vim.uv` bridge).

## Mechanics

Every not-yet-ported module `lib/vim/<module>/init.lua` consists of:

```lua
return require("lib.vim._stub")("<module>")
```

`lib.vim._stub` returns a table whose function accesses mirror the API surface,
but throw a clear error on actual **call**:

```
lib.vim.<module>.<fn>: not yet implemented for classic Vim.
Under Neovim, use lib.nvim.<module> instead.
```

This lets dependent plugins already program against `lib.vim.*` while the real
implementations are added over time.

## Porting a module

Replace `lib/vim/<module>/init.lua` with a real implementation that offers the
**same public signature** as `lib.nvim.<module>`, but internally uses
`vim.fn`/Vimscript (`vim.fn.*`, `vim.cmd`, `:command`, `:map`, `execute()` …)
instead of `vim.api`/`vim.uv`. Then set the status below to ✅.

## Status

| Module                 | Status | Note                                                 |
| ---------------------- | :----: | ---------------------------------------------------- |
| `lib.vim.notify`       |   ⬜   | `:echohl`/`echomsg` possible                         |
| `lib.vim.map`          |   ⬜   | `:map`/`mapset()`                                    |
| `lib.vim.usercmd`      |   ⬜   | `:command!`                                          |
| `lib.vim.autocmd`      |   ⬜   | `:autocmd`/`:augroup`                                |
| `lib.vim.buffer`       |   ⬜   | `getline()`/`setline()`/`bufnr()`                    |
| `lib.vim.buf_win_tab`  |   ⬜   | `win_*()`/`tabpage*()`                               |
| `lib.vim.window`       |   ⬜   | `win_*()`                                            |
| `lib.vim.ui`           |   ⬜   | `popup_*()`/`inputlist()` (involved)                 |
| `lib.vim.fs`           |   ⬜   | `glob()`/`fnamemodify()`/`filereadable()`            |
| `lib.vim.cross`        |   ⬜   | `has()`/`system()`/`job_start()`                     |
| `lib.vim.normalize`    |   ⬜   | `fnamemodify()`/`substitute()`                       |
| `lib.vim.git`          |   ⬜   | `system()`                                           |
| `lib.vim.terminal`     |   ⬜   | `term_*()` (Vim) instead of `:terminal` buffer       |
| `lib.vim.require`      |   ⬜   | only relevant with `+lua`                            |
| `lib.vim.lua_ls`       |   ⬜   | pure path/string handling, ports well                |
| `lib.vim.core`         |   ⬜   | `has_exec` → `executable()`; `simple_echo` → `echo`  |

Legend: ✅ ported · 🟡 partial · ⬜ stub (placeholder)

> Note: much of `lib.nvim.*` builds on functionality that does not exist in
> classic Vim (e.g. extmarks, `vim.uv`, floating windows). Such parts stay
> permanently without a Vim counterpart; that is expected and fine —
> `lib.vim.*` only covers the portable part.
