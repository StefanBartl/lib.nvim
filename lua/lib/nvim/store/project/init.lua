---@module 'lib.nvim.store.project'
--- Persistent state keyed by project, so reopening the same project (even on
--- a different machine, via synced dotfiles/config) finds the same state
--- again — as opposed to `lib.nvim.cache.disk`, which is keyed by a
--- caller-chosen `namespace` with no notion of "which project is this for".
---
--- Combines two existing primitives, adding nothing but the root-resolution
--- step between them:
---   - `lib.nvim.fs.project_key` — git root of the given/current path (falls
---     back to the path itself when not in a work-tree), normalized.
---   - `lib.nvim.cache.disk` — namespaced JSON persistence with TTL,
---     `pcall`-guarded read/write.
---
--- `project_key` is used instead of calling `lib.nvim.git.repo_root`
--- directly: it already implements "git root, else the given path" with a
--- cached, marker-based lookup (no `git` subprocess per call), and its
--- output is already normalized — exactly the root-resolution this module
--- needs.
---
---```lua
--- local store = require("lib.nvim.store.project")
---
--- store.save("cascade/anchors", { version = 1, files = { ... } })
--- local data = store.load("cascade/anchors")  -- nil if missing/unreadable/expired
--- store.clear("cascade/anchors")
---```

require("lib.nvim.store.project.@types")

local project_key = require("lib.nvim.fs.project_key")
local disk = require("lib.nvim.cache.disk")

local M = {}

---Deterministic, filesystem-safe short key for an arbitrary string.
---@internal
---Not cryptographic — only used to turn an absolute project path into a
---directory name that can't collide with path separators.
---@param s string
---@return string
local function short_hash(s)
  local h = 5381
  for i = 1, #s do
    h = (h * 33 + s:byte(i)) % 4294967296
  end
  return string.format("%08x", h)
end

---@internal
---Directory `lib.nvim.cache.disk` should use for the project resolved from
---`opts.path` (default cwd).
---@param opts? Lib.Store.Project.Opts
---@return string dir
---@return string root
local function resolve(opts)
  opts = opts or {}
  local root = project_key(opts.path)
  local base = opts.dir or (vim.fn.stdpath("cache") .. "/lib.nvim/store/project")
  return base .. "/" .. short_hash(root), root
end

---The resolved, normalized project root backing `key`'s storage for the
---current (or `opts.path`) project. Exposed for diagnostics/tests.
---@param opts? Lib.Store.Project.Opts
---@return string
function M.root(opts)
  local _, root = resolve(opts)
  return root
end

---Persist `data` under `key`, namespaced to the current project.
---@param key string
---@param data any
---@param opts? Lib.Store.Project.SaveOpts
---@return boolean ok
---@return string|nil err
function M.save(key, data, opts)
  local dir = resolve(opts)
  return disk.save(key, data, { dir = dir })
end

---Load the value saved under `key` for the current project, or `nil` if
---missing, unreadable, or expired (per `opts.ttl_seconds`).
---@param key string
---@param opts? Lib.Store.Project.LoadOpts
---@return any|nil data
function M.load(key, opts)
  opts = opts or {}
  local dir = resolve(opts)
  return disk.load(key, { dir = dir, ttl_seconds = opts.ttl_seconds })
end

---Remove the stored value for `key` in the current project.
---@param key string
---@param opts? Lib.Store.Project.Opts
---@return boolean ok
function M.clear(key, opts)
  local dir = resolve(opts)
  return disk.clear(key, { dir = dir })
end

---Report on-disk state for `key` in the current project, without decoding
---the full payload.
---@param key string
---@param opts? Lib.Store.Project.Opts
---@return Lib.Cache.Stats
function M.stats(key, opts)
  local dir = resolve(opts)
  return disk.stats(key, { dir = dir })
end

---@type Lib.Store.Project
return M
