---@meta
---@module 'lib.nvim.fs.json.@types'

---@class Lib.Fs.Json
---@field read fun(path: string): table|nil, string|nil Read and JSON-decode `path`.
---@field write fun(path: string, tbl: table): boolean, string|nil JSON-encode `tbl` and write it to `path` atomically.

return {}
