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

---@type Lib.Fs.ScanRoots
return M
