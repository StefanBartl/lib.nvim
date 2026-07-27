---@meta
---@module 'lib.nvim.fs.find_root.@types'

---Options for the cached marker-based root finder.
---@class Lib.Fs.FindRoot.Opts
---@field markers     string[]? Marker names (files or folders) that mark a root; `*`/`?` globs allowed (e.g. "*.rockspec"). Default { ".git" }.
---@field capacity    integer?  LRU cache capacity, keyed per directory. Default 256, or 512 when `cache_chain` is set.
---@field cache       boolean?  Enable the per-directory LRU cache. Default true.
---@field cache_chain boolean?  Cache the root for every directory passed on the way up, not just the queried one. Default false.
---@field skip_dirs   string[]? Directory basenames that can never hold a root (e.g. "node_modules", ".venv"); the walk starts above the topmost occurrence in the queried path. Default none.
---@field max_depth   integer?  Maximum number of levels the walk may climb; 0 searches only the queried directory. Default unbounded.

---A constructed root finder.
---@class Lib.Fs.FindRoot
---@field find  fun(path: string): string|nil  Nearest ancestor dir containing a marker, or nil.
---@field clear fun()                            Drop all cached lookups.
