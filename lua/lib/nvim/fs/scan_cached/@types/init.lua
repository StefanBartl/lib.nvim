---@meta
---@module 'lib.nvim.fs.scan_cached.@types'

---@class Lib.Fs.ScanCached.Opts
---@field kind Lib.Fs.CollectRecursive.Kind|nil Defaults to "files".
---@field ignore (fun(abs_path: string, is_dir: boolean): boolean)|nil Forwarded to `collect_recursive`.
---@field ttl_seconds integer|nil Cache freshness window in seconds (default 5).
---@field refresh boolean|nil Force a rescan, bypassing the cache, and refresh it.

---@class Lib.Fs.ScanCached
---@field scan fun(root: string, opts?: Lib.Fs.ScanCached.Opts): string[]

return {}
