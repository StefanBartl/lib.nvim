---@meta
---@module 'lib.nvim.fs.find_root.@types'

---Options for the cached marker-based root finder.
---@class Lib.Fs.FindRoot.Opts
---@field markers  string[]? Marker names (files or folders) that mark a root. Default { ".git" }.
---@field capacity integer?  LRU cache capacity, keyed per directory. Default 256.
---@field cache    boolean?  Enable the per-directory LRU cache. Default true.

---A constructed root finder.
---@class Lib.Fs.FindRoot
---@field find  fun(path: string): string|nil  Nearest ancestor dir containing a marker, or nil.
---@field clear fun()                            Drop all cached lookups.
