---@meta
---@module 'lib.nvim.checkpoint.@types'

---@class Lib.Checkpoint.CreateOpts
---@field dir? string Override the checkpoint root (default `stdpath("cache") .. "/lib.nvim/checkpoints"`).

---@class Lib.Checkpoint.Entry
---@field path string The original, absolute path being tracked.
---@field backup string|nil Absolute path to the backup copy; `nil` when `existed` is `false`.
---@field existed boolean Whether `path` had a file on disk at `M.create` time.
---@field size integer|nil Byte size of the backed-up file; `nil` when `existed` is `false`.

---@class Lib.Checkpoint
---@field id string
---@field dir string The checkpoint's own backup directory.
---@field created_at integer `os.time()` at `M.create`.
---@field entries Lib.Checkpoint.Entry[]

---@class Lib.Checkpoint.RestoreError
---@field path string
---@field err string|nil

---@class Lib.Checkpoint.Module
---@field create fun(paths: string[], opts?: Lib.Checkpoint.CreateOpts): Lib.Checkpoint|nil, string|nil
---@field restore fun(checkpoint: Lib.Checkpoint): boolean, Lib.Checkpoint.RestoreError[]
---@field discard fun(checkpoint: Lib.Checkpoint): boolean

return {}
