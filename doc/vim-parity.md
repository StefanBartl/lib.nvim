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
instead of `vim.api`/`vim.uv`. Then set the status below to `ported`.

## Status

| Module                 | Status  | Note                                                 |
| ---------------------- | :-----: | ---------------------------------------------------- |
| `lib.vim.notify`       |  stub   | `:echohl`/`echomsg` possible                         |
| `lib.vim.map`          |  stub   | `:map`/`mapset()`                                    |
| `lib.vim.usercmd`      |  stub   | `:command!`                                          |
| `lib.vim.autocmd`      |  stub   | `:autocmd`/`:augroup`                                |
| `lib.vim.buffer`       |  stub   | `getline()`/`setline()`/`bufnr()`                    |
| `lib.vim.buf_win_tab`  |  stub   | `win_*()`/`tabpage*()`                               |
| `lib.vim.window`       |  stub   | `win_*()`                                            |
| `lib.vim.ui`           |  stub   | `popup_*()`/`inputlist()` (involved)                 |
| `lib.vim.fs`           |  stub   | `glob()`/`fnamemodify()`/`filereadable()`            |
| `lib.vim.cross`        |  stub   | `has()`/`system()`/`job_start()`                     |
| `lib.vim.normalize`    |  stub   | `fnamemodify()`/`substitute()`                       |
| `lib.vim.git`          |  stub   | `system()`                                           |
| `lib.vim.terminal`     |  stub   | `term_*()` (Vim) instead of `:terminal` buffer       |
| `lib.vim.require`      |  stub   | only relevant with `+lua`                            |
| `lib.vim.lua_ls`       |  stub   | pure path/string handling, ports well                |
| `lib.vim.core`         |  stub   | `has_exec` → `executable()`; `simple_echo` → `echo`  |

Legend: `ported` · `partial` · `stub` (placeholder)

> Note: much of `lib.nvim.*` builds on functionality that does not exist in
> classic Vim (e.g. extmarks, `vim.uv`, floating windows). Such parts stay
> permanently without a Vim counterpart; that is expected and fine —
> `lib.vim.*` only covers the portable part.
