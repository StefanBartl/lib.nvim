---@meta
---@module 'lib.nvim.fs.scan_roots.@types'

---@class Lib.Fs.ScanRoots.Opts
---@field ignore_dirs string[]|nil Directory names to skip anywhere in the tree (e.g. "node_modules", ".git").
---@field cache_path string|nil Path to a JSON cache file; when given, reused if fresh (see `ttl_seconds`).
---@field ttl_seconds integer|nil Cache freshness window in seconds; `nil` means the cache never expires once written.
---@field kind Lib.Fs.CollectRecursive.Kind|nil Defaults to "files".

---@class Lib.Fs.ScanRoots.Cache
---@field saved_at integer
---@field paths string[]

---@class Lib.Fs.ScanRoots
---@field scan fun(roots: string[], opts?: Lib.Fs.ScanRoots.Opts): string[]

return {}
