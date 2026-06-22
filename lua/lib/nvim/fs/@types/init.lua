---@meta
---@module 'lib.nvim.fs.@types'

---@class Lib.Fs
---@field path Lib.Fs.Path
---@field query Lib.Fs.Query
---@field transform Lib.Fs.Transform
---@field write Lib.FS.Write

---@class Lib.Fs.ALL
---@field joinpath fun(parts: string[]): string
---@field ensure_dir fun(path: string): boolean, string?
---@field is_subpath fun(path: string, base: string): boolean
---@field is_dir fun(p: string): boolean
---@field find_upward_dir fun(names: string[], from: string): string|nil
---@field dedup fun(entries: string[]): string[]
---@field path_shorten fun(path: string, max_len: integer): string
---@field relpath fun(path: string, base: string): string
---@field write_to_file fun(path: string, content: string): boolean, string|nil # Write string content to given path. Makes sure that directory exists. Return sucess boolean and in cade of no success string notice

return {}
