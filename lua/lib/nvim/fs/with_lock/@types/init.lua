---@meta
---@module 'lib.nvim.fs.with_lock.@types'

---@class Lib.Fs.WithLockOpts
---@field wait_ms? integer                                              Longest wait for a lock held by someone else (default 2000).
---@field stale_s? integer                                              Age in seconds after which a lock counts as left behind and is taken over (default 10). Keep the locked work well below it.
---@field create_exclusive? fun(path: string, content: string): boolean, string|nil  Test seam: how the lock file is made (default `lib.nvim.fs.create_exclusive`). It must write `content` as given: the release deletes the lock only while it still holds it. The takeover guard is always made by the real one.

return {}
