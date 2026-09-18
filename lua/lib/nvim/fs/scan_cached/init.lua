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

---@internal
---The key carries every input that changes the result. `opts.ignore`
---decides which paths are emitted, so two callers with different predicates
---must not share an entry; it goes in by identity, there being nothing else
---to key a closure on. The cached entry also keeps a reference to the
---predicate (see `remember`) so its address cannot be recycled by a new
---closure while the entry lives, and a hit re-checks that reference.
---@param root string
---@param kind string
---@param ignore function|nil
---@return string
local function cache_key(root, kind, ignore)
  return root .. ":" .. kind .. ":" .. (ignore and tostring(ignore) or "-")
end

---@internal
---@param paths string[]
---@param ignore function|nil
---@return { paths: string[], ignore: function|nil }
local function remember(paths, ignore)
  return { paths = paths, ignore = ignore }
end

---@internal
---@param entry { paths: string[], ignore: function|nil }|nil
---@param ignore function|nil
---@return string[]|nil
local function recall(entry, ignore)
  if entry and entry.ignore == ignore then
    return entry.paths
  end
  return nil
end

---Recursively scan `root`, honoring an in-memory TTL cache keyed by root,
---`kind` and the `ignore` predicate. Pass `opts.refresh = true` to force a
---rescan.
---
---`errors` is `collect_recursive`'s list of unreadable directories, or
---`nil`. A walk that reported any is returned but not cached: a root that
---is momentarily unavailable would otherwise answer "no files here" for
---the whole TTL.
---@param root string
---@param opts? Lib.Fs.ScanCached.Opts
---@return string[] paths
---@return string[]|nil errors
---@see lib.nvim.fs.scan_roots.scan
function M.scan(root, opts)
  opts = opts or {}
  local kind = opts.kind or "files"
  local ttl = opts.ttl_seconds or DEFAULT_TTL_SECONDS
  local key = cache_key(root, kind, opts.ignore)

  -- Re-namespaced per call rather than memoized at module scope: cheap (a
  -- table lookup by name), and it lets different callers use this module
  -- with different `ttl_seconds` without one call's TTL silently governing
  -- another's cache entries.
  local ns = memory.namespace("lib.nvim.fs.scan_cached", { ttl = ttl })

  if not opts.refresh then
    local cached = recall(ns.get(key), opts.ignore)
    if cached then
      return cached
    end
  end

  local found, errors = collect_recursive.collect(root, { kind = kind, ignore = opts.ignore })
  if not errors then
    ns.set(key, remember(found, opts.ignore))
  end
  return found, errors
end

---Async counterpart to `scan`: same TTL cache, but a cache miss walks via
---`collect_recursive.collect_async` instead of blocking the main loop.
---A cache hit still calls `on_done` — `vim.schedule`-dispatched, matching
---the miss path, so callers can treat both uniformly.
---@param root string
---@param opts? Lib.Fs.ScanCached.Opts
---@param on_done fun(paths: string[], errors: string[]|nil)
---@return nil
---@see lib.nvim.fs.collect_recursive.collect_async
function M.scan_async(root, opts, on_done)
  opts = opts or {}
  local kind = opts.kind or "files"
  local ttl = opts.ttl_seconds or DEFAULT_TTL_SECONDS
  local key = cache_key(root, kind, opts.ignore)

  local ns = memory.namespace("lib.nvim.fs.scan_cached", { ttl = ttl })

  if not opts.refresh then
    local cached = recall(ns.get(key), opts.ignore)
    if cached then
      vim.schedule(function()
        on_done(cached)
      end)
      return
    end
  end

  collect_recursive.collect_async(
    root,
    { kind = kind, ignore = opts.ignore },
    function(found, errors)
      if not errors then
        ns.set(key, remember(found, opts.ignore))
      end
      on_done(found, errors)
    end
  )
end

---@type Lib.Fs.ScanCached
return M
