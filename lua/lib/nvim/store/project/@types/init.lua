---@meta
---@module 'lib.nvim.store.project.@types'

---@class Lib.Store.Project.Opts
---@field path? string Path to resolve the project root from (default cwd). Only affects root resolution, not where the caller's own files live.
---@field dir? string Override the parent storage directory (default `stdpath("cache") .. "/lib.nvim/store/project"`); each project gets one subdirectory under it.

---@class Lib.Store.Project.SaveOpts : Lib.Store.Project.Opts

---@class Lib.Store.Project.LoadOpts : Lib.Store.Project.Opts
---@field ttl_seconds? integer Treat entries older than this as expired (returns `nil`, does not delete)

--- `lib.nvim.store.project` module surface: project-scoped persistent state.
---@class Lib.Store.Project
---@field root fun(opts?: Lib.Store.Project.Opts): string
---@field save fun(key: string, data: any, opts?: Lib.Store.Project.SaveOpts): boolean, string?
---@field load fun(key: string, opts?: Lib.Store.Project.LoadOpts): any
---@field clear fun(key: string, opts?: Lib.Store.Project.Opts): boolean
---@field stats fun(key: string, opts?: Lib.Store.Project.Opts): Lib.Cache.Stats

return {}
