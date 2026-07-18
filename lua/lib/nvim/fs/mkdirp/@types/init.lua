---@meta
---@module 'lib.nvim.fs.mkdirp.@types'

---Recursive directory creation (`mkdir -p`) built purely on libuv — safe to
---call from a fast event context, unlike `vim.fn.mkdir(path, "p")`.
---@alias Lib.Fs.Mkdirp fun(path: string): boolean, string?
