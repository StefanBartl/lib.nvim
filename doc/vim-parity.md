# `lib.vim` — Portierungsstatus (Vim-Parität)

Ziel: für jedes Modul aus `lib.nvim.*` ein API-gleiches Pendant in `lib.vim.*`,
das unter **klassischem Vim** (ohne die Neovim-`vim.api`/`vim.uv`-Bridge)
funktioniert.

## Mechanik

Jedes noch nicht portierte Modul `lib/vim/<modul>/init.lua` besteht aus:

```lua
return require("lib.vim._stub")("<modul>")
```

`lib.vim._stub` liefert eine Tabelle, deren Funktionszugriffe die API-Oberfläche
spiegeln, bei tatsächlichem **Aufruf** aber einen klaren Fehler werfen:

```
lib.vim.<modul>.<fn>: noch nicht für klassisches Vim implementiert.
Unter Neovim stattdessen lib.nvim.<modul> verwenden.
```

So können abhängige Plugins bereits gegen `lib.vim.*` programmieren, während die
echten Implementierungen nach und nach ergänzt werden.

## Portieren eines Moduls

`lib/vim/<modul>/init.lua` durch eine echte Implementierung ersetzen, die die
**gleiche öffentliche Signatur** wie `lib.nvim.<modul>` anbietet, intern aber
`vim.fn`/Vimscript (`vim.fn.*`, `vim.cmd`, `:command`, `:map`, `execute()` …)
statt `vim.api`/`vim.uv` nutzt. Anschließend Status unten auf ✅ setzen.

## Status

| Modul                  | Status | Anmerkung                                            |
| ---------------------- | :----: | --------------------------------------------------- |
| `lib.vim.notify`       |   ⬜   | `:echohl`/`echomsg` möglich                          |
| `lib.vim.map`          |   ⬜   | `:map`/`mapset()`                                    |
| `lib.vim.usercmd`      |   ⬜   | `:command!`                                          |
| `lib.vim.autocmd`      |   ⬜   | `:autocmd`/`:augroup`                                |
| `lib.vim.buffer`       |   ⬜   | `getline()`/`setline()`/`bufnr()`                    |
| `lib.vim.buf_win_tab`  |   ⬜   | `win_*()`/`tabpage*()`                               |
| `lib.vim.window`       |   ⬜   | `win_*()`                                            |
| `lib.vim.ui`           |   ⬜   | `popup_*()`/`inputlist()` (aufwändig)                |
| `lib.vim.fs`           |   ⬜   | `glob()`/`fnamemodify()`/`filereadable()`            |
| `lib.vim.cross`        |   ⬜   | `has()`/`system()`/`job_start()`                     |
| `lib.vim.normalize`    |   ⬜   | `fnamemodify()`/`substitute()`                       |
| `lib.vim.git`          |   ⬜   | `system()`                                           |
| `lib.vim.terminal`     |   ⬜   | `term_*()` (Vim) statt `:terminal`-Buffer            |
| `lib.vim.require`      |   ⬜   | nur relevant mit `+lua`                              |
| `lib.vim.lua_ls`       |   ⬜   | reines Pfad-/String-Handling, gut portierbar         |
| `lib.vim.core`         |   ⬜   | `has_exec` → `executable()`; `simple_echo` → `echo`  |

Legende: ✅ portiert · 🟡 teilweise · ⬜ Stub (Platzhalter)

> Hinweis: Vieles in `lib.nvim.*` baut auf Funktionalität auf, die es in
> klassischem Vim nicht gibt (z. B. Extmarks, `vim.uv`, Floating Windows). Solche
> Teile bleiben dauerhaft ohne Vim-Pendant; das ist erwartet und in Ordnung —
> `lib.vim.*` deckt nur den portierbaren Teil ab.
