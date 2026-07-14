---@meta
---@module 'lib.nvim.fs.create_entry.@types'

---Create a file or directory relative to a parent directory.
---@alias Lib.Fs.CreateEntry fun(parent_dir: string, name: string): boolean, ("file"|"directory")?, string?
