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

---@internal
---A cache file answers only the exact question it was written for: the same
---roots, `kind` and ignore list. Anything else is a different scan that
---happens to share a file name, and its answer must not be handed back --
---with `ttl_seconds` unset it would be, forever. A file written before these
---fields existed fails the check once and is rewritten.
---@param cached table
---@param roots string[]
---@param kind string
---@param ignore_dirs string[]
---@return boolean
local function cache_matches(cached, roots, kind, ignore_dirs)
  return type(cached.paths) == "table"
    and cached.kind == kind
    and vim.deep_equal(cached.roots, roots)
    and vim.deep_equal(cached.ignore_dirs, ignore_dirs)
end

---@internal
---@param roots string[]
---@param kind string
---@param ignore_dirs string[]
---@param paths string[]
---@return Lib.Fs.ScanRoots.Cache
local function cache_payload(roots, kind, ignore_dirs, paths)
  return {
    saved_at = os.time(),
    roots = roots,
    kind = kind,
    ignore_dirs = ignore_dirs,
    paths = paths,
  }
end

---Scan `roots` for files/dirs, honoring an optional cache.
---
---`errors` collects `collect_recursive`'s unreadable-directory reports
---across all roots, or is `nil`. A scan that reported any is returned but
---not written to `cache_path`: with `ttl_seconds` unset the cache never
---expires, so "this root was unavailable once" must not become "this
---project has no files" across restarts.
---@param roots string[]
---@param opts? Lib.Fs.ScanRoots.Opts
---@return string[] paths
---@return string[]|nil errors
---@see lib.nvim.fs.scan_cached.scan
function M.scan(roots, opts)
  opts = opts or {}
  local ignore_dirs = opts.ignore_dirs or {}
  local kind = opts.kind or "files"

  if opts.cache_path then
    local cached = json.read(opts.cache_path)
    if cached and cache_matches(cached, roots, kind, ignore_dirs) then
      local fresh = opts.ttl_seconds == nil
        or (os.time() - (cached.saved_at or 0)) <= opts.ttl_seconds
      if fresh then
        return cached.paths
      end
    end
  end

  -- The blocking scan is sequential by design; use `scan_async` with `opts.concurrency` for parallel roots.
  local merged, errors = {}, {}
  for _, root in ipairs(roots) do
    local found, root_errors = collect_recursive.collect(root, {
      kind = kind,
      ignore = function(path)
        return is_ignored(path, ignore_dirs)
      end,
    })
    for _, p in ipairs(found) do
      merged[#merged + 1] = p
    end
    for _, e in ipairs(root_errors or {}) do
      errors[#errors + 1] = e
    end
  end

  if opts.cache_path and #errors == 0 then
    json.write(opts.cache_path, cache_payload(roots, kind, ignore_dirs, merged))
  end

  return merged, (#errors > 0) and errors or nil
end

---Async counterpart to `scan`: same cache semantics (still read/written
---synchronously — a single small JSON file, not the part that scales badly),
---but the actual per-root walk uses `collect_recursive.collect_async`
---instead of blocking the main loop. Roots are walked one at a time unless
---`opts.concurrency` (> 1) allows several in flight; the result is always
---merged in the order of `roots`. `on_done(paths, errors)` fires exactly once, always
---`vim.schedule`-dispatched (directly on a cache hit, via the async walk
---otherwise); `errors` follows the same rule as in `scan`.
---@param roots string[]
---@param opts? Lib.Fs.ScanRoots.Opts
---@param on_done fun(paths: string[], errors: string[]|nil)
---@return nil
---@see lib.nvim.fs.scan_cached.scan_async
function M.scan_async(roots, opts, on_done)
  opts = opts or {}
  local ignore_dirs = opts.ignore_dirs or {}
  local kind = opts.kind or "files"

  if opts.cache_path then
    local cached = json.read(opts.cache_path)
    if cached and cache_matches(cached, roots, kind, ignore_dirs) then
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

  -- Roots are walked by `async.map_limit`: at most `opts.concurrency` at a time (default 1 -- one after the
  -- other, as before). The result is merged in the order of `roots`, whichever root finishes first, so the
  -- answer does not depend on timing. A single root is still walked directory by directory.
  local concurrency = opts.concurrency or 1
  local ignore = function(path)
    return is_ignored(path, ignore_dirs)
  end
  require("lib.nvim.async").map_limit(roots, concurrency, function(root, _, done)
    local cancel = collect_recursive.collect_async(
      root,
      { kind = kind, ignore = ignore },
      function(found, root_errors)
        done({ found = found, errors = root_errors })
      end
    )
    return { stop = cancel }
  end, function(results, worker_errors)
    local merged, errors = {}, {}
    for i, root in ipairs(roots) do
      local r = results[i]
      if r then
        for _, p in ipairs(r.found) do
          merged[#merged + 1] = p
        end
        for _, e in ipairs(r.errors or {}) do
          errors[#errors + 1] = e
        end
      elseif worker_errors[i] then
        errors[#errors + 1] = root .. ": " .. tostring(worker_errors[i])
      end
    end
    if opts.cache_path and #errors == 0 then
      json.write(opts.cache_path, cache_payload(roots, kind, ignore_dirs, merged))
    end
    -- `map_limit` vim.schedule-dispatches `on_done`, so the cache-hit branch above and this one both
    -- deliver on a scheduled callback.
    on_done(merged, (#errors > 0) and errors or nil)
  end)
end

---@type Lib.Fs.ScanRoots
return M
