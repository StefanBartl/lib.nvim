# `lib.nvim.buf_win_tab.get_option`

Read a buffer option across a wide range of Neovim versions.

Neovim moved buffer-option access from `nvim_buf_get_option` to
`nvim_get_option_value` and deprecated the former; older builds lack the
latter. This helper tries every known route, each guarded by `pcall`, and
returns the first value it can obtain — so callers stop caring which build
they run on.

Routes attempted, in order:

1. `nvim_get_option_value(name, { buf = bufnr })` — modern API
2. `nvim_buf_get_option(bufnr, name)` — deprecated, broadly compatible
3. `vim.bo[name]` — when `bufnr` is the current buffer
4. `nvim_buf_call(bufnr, ...)` + `vim.bo[name]` — evaluate in the buffer's context

## Usage

```lua
local get_option = require("lib.nvim.buf_win_tab.get_option")

local ft = get_option(bufnr, "filetype")   --> "lua"
local mod = get_option(bufnr, "modified")  --> false
local gone = get_option(9999, "filetype")  --> nil (invalid buffer)
```

## Returns

| # | Type    | Meaning                                        |
|---|---------|------------------------------------------------|
| 1 | `any?`  | Option value, or `nil` if every route failed   |
