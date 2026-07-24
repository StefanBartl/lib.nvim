---@module 'lib.nvim.fs.scan_cached'
--- Recursively scan one root directory, memoized in-memory with a TTL — the
--- session-lifetime counterpart to `scan_roots` (which persists to disk
--- across restarts). Built for repeated audit/report-style scans of the same
--- root within a single Neovim session (e.g. re-running a report with a
--- different filter), where a few seconds of staleness is fine and a fresh
--- walk on every call is not.
---
---```lua
--- local scan_cached = require("lib.nvim.fs.scan_cached")
---
--- local files = scan_cached.scan("/repo/lua", { ttl_seconds = 5 })
--- -- within 5s, a repeat call reuses the cached list instead of rescanning:
--- local same = scan_cached.scan("/repo/lua", { ttl_seconds = 5 })
--- -- force a rescan on demand:
--- local fresh = scan_cached.scan("/repo/lua", { ttl_seconds = 5, refresh = true })
---```

require("lib.nvim.fs.scan_cached.@types")

local collect_recursive = require("lib.nvim.fs.collect_recursive")
local memory = require("lib.nvim.cache.memory")

local M = {}

---@type integer
local DEFAULT_TTL_SECONDS = 5

---Recursively scan `root`, honoring an in-memory TTL cache keyed by
---`root .. ":" .. kind`. Pass `opts.refresh = true` to force a rescan.
---@param root string
---@param opts? Lib.Fs.ScanCached.Opts
---@return string[]
function M.scan(root, opts)
  opts = opts or {}
  local kind = opts.kind or "files"
  local ttl = opts.ttl_seconds or DEFAULT_TTL_SECONDS
  local key = root .. ":" .. kind

  -- Re-namespaced per call rather than memoized at module scope: cheap (a
  -- table lookup by name), and it lets different callers use this module
  -- with different `ttl_seconds` without one call's TTL silently governing
  -- another's cache entries.
  local ns = memory.namespace("lib.nvim.fs.scan_cached", { ttl = ttl })

  if not opts.refresh then
    local cached = ns.get(key)
    if cached then
      return cached
    end
  end

  local found = collect_recursive.collect(root, { kind = kind, ignore = opts.ignore })
  ns.set(key, found)
  return found
end

---@type Lib.Fs.ScanCached
return M
