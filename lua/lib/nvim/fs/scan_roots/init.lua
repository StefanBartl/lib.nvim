---@module 'lib.nvim.fs.scan_roots'
--- Scan multiple root directories for files (or dirs), with optional
--- directory-name ignoring and an optional TTL-based on-disk cache.
---
--- Builds on `lib.nvim.fs.collect_recursive` (the actual walk) and
--- `lib.nvim.fs.json` (cache persistence) — required by full path, logic is
--- not duplicated here.
---
---```lua
--- local scan_roots = require("lib.nvim.fs.scan_roots")
---
--- local files = scan_roots.scan({ "/repo/src", "/repo/lua" }, {
---   ignore_dirs = { "node_modules", ".git" },
---   cache_path = vim.fn.stdpath("cache") .. "/my_plugin/scan.json",
---   ttl_seconds = 60,
--- })
---```

require("lib.nvim.fs.scan_roots.@types")

local collect_recursive = require("lib.nvim.fs.collect_recursive")
local json = require("lib.nvim.fs.json")

local M = {}

---@internal
---True when `path` ends in a path component matching one of `ignore_dirs`.
---@param path string
---@param ignore_dirs string[]
---@return boolean
local function is_ignored(path, ignore_dirs)
  for _, d in ipairs(ignore_dirs) do
    local pat = vim.pesc(d)
    if path:match("[/\\]" .. pat .. "$") or path:match("[/\\]" .. pat .. "[/\\]") then
      return true
    end
  end
  return false
end

---Scan `roots` for files/dirs, honoring an optional cache.
---@param roots string[]
---@param opts? Lib.Fs.ScanRoots.Opts
---@return string[]
---@see lib.nvim.fs.scan_cached.scan
function M.scan(roots, opts)
  opts = opts or {}
  local ignore_dirs = opts.ignore_dirs or {}
  local kind = opts.kind or "files"

  if opts.cache_path then
    local cached = json.read(opts.cache_path)
    if cached and type(cached.paths) == "table" then
      local fresh = opts.ttl_seconds == nil
        or (os.time() - (cached.saved_at or 0)) <= opts.ttl_seconds
      if fresh then
        return cached.paths
      end
    end
  end

  -- Sequential by design: bounded-concurrency async scanning was left out
  -- for simplicity. Callers needing that can call `M.scan` once per root
  -- from their own async scheduler instead.
  local merged = {}
  for _, root in ipairs(roots) do
    local found = collect_recursive.collect(root, {
      kind = kind,
      ignore = function(path)
        return is_ignored(path, ignore_dirs)
      end,
    })
    for _, p in ipairs(found) do
      merged[#merged + 1] = p
    end
  end

  if opts.cache_path then
    json.write(opts.cache_path, { saved_at = os.time(), paths = merged })
  end

  return merged
end

---Async counterpart to `scan`: same cache semantics (still read/written
---synchronously — a single small JSON file, not the part that scales badly),
---but the actual per-root walk uses `collect_recursive.collect_async`
---instead of blocking the main loop. Roots are still walked one at a time,
---sequentially — see `collect_async`'s own note on why this isn't
---parallelized. `on_done(paths)` fires exactly once, always
---`vim.schedule`-dispatched (directly on a cache hit, via `collect_async`
---otherwise).
---@param roots string[]
---@param opts? Lib.Fs.ScanRoots.Opts
---@param on_done fun(paths: string[])
---@return nil
---@see lib.nvim.fs.scan_cached.scan_async
function M.scan_async(roots, opts, on_done)
  opts = opts or {}
  local ignore_dirs = opts.ignore_dirs or {}
  local kind = opts.kind or "files"

  if opts.cache_path then
    local cached = json.read(opts.cache_path)
    if cached and type(cached.paths) == "table" then
      local fresh = opts.ttl_seconds == nil
        or (os.time() - (cached.saved_at or 0)) <= opts.ttl_seconds
      if fresh then
        vim.schedule(function()
          on_done(cached.paths)
        end)
        return
      end
    end
  end

  local merged = {}
  local idx = 0

  local function next_root()
    idx = idx + 1
    local root = roots[idx]
    if not root then
      if opts.cache_path then
        json.write(opts.cache_path, { saved_at = os.time(), paths = merged })
      end
      -- `collect_recursive.collect_async` already vim.schedule-dispatches
      -- its own on_done, and every step here runs from inside that
      -- dispatch, so this final call is already on a scheduled callback —
      -- no extra vim.schedule needed to match the cache-hit branch's
      -- contract above.
      on_done(merged)
      return
    end
    collect_recursive.collect_async(root, {
      kind = kind,
      ignore = function(path)
        return is_ignored(path, ignore_dirs)
      end,
    }, function(found)
      for _, p in ipairs(found) do
        merged[#merged + 1] = p
      end
      next_root()
    end)
  end

  next_root()
end

---@type Lib.Fs.ScanRoots
return M
