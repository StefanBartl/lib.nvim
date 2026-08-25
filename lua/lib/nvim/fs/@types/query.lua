---@meta
---@module 'lib.nvim.fs.@types.query'

---Options for `lib.nvim.fs.is_subpath`.
---
---Passing a table at all (even an empty one) switches both sides from a plain
---`vim.fs.normalize` to `lib.nvim.fs.normkey`, which also uppercases a Windows
---drive letter and collapses duplicate separators.
---@class Lib.Fs.IsSubpathOpts
---@field realpath? boolean Resolve symlinks and Windows 8.3 short names via `uv.fs_realpath`. Default true.

---@class Lib.Fs.Query
---@field is_subpath fun(path: string, base: string, opts?: Lib.Fs.IsSubpathOpts): boolean
---@field is_dir fun(p: string): boolean
---@field find_upward_dir fun(names: string[], from: string): string|nil

return {}
