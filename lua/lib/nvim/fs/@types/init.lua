---@meta
---@module 'lib.nvim.fs.@types'

--- CDX: `Lib.Fs` and `Lib.Fs.ALL` are stale scaffolding from the initial
--- CDX: commit. There is no `lib.nvim.fs` aggregate module, so the
--- CDX: path/query/transform/write grouping below is fictional, and `ALL` has
--- CDX: drifted (`dedup` names no module, `path_shorten` lost its `opts`). The
--- CDX: real flat surface is `lua/lib/@types/all_functions.lua`; the only
--- CDX: referent is the already-flagged `Lib.Modules.fs` chain. Left as-is
--- CDX: pending an external-consumer check.
---@class Lib.Fs
---@field path Lib.Fs.Path
---@field query Lib.Fs.Query
---@field transform Lib.Fs.Transform
---@field write Lib.Fs.Write

---@class Lib.Fs.ALL
---@field joinpath fun(parts: string[]): string
---@field ensure_dir fun(path: string): boolean, string?
---@field is_subpath fun(path: string, base: string, opts?: Lib.Fs.IsSubpathOpts): boolean
---@field is_dir fun(p: string): boolean
---@field find_upward_dir fun(names: string[], from: string): string|nil
---@field dedup fun(entries: string[]): string[]
---@field path_shorten fun(path: string, max_len: integer): string
---@field relpath fun(path: string, base: string): string
---@field write_to_file fun(path: string, content: string): boolean, string|nil # Write content to path, creating the parent directory. Returns a success boolean, plus a message on failure.

return {}
