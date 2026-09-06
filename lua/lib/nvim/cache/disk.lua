---@module 'lib.nvim.cache.disk'
--- Persistent JSON disk cache with TTL, keyed by a simple `namespace` string.
---
--- Complements the in-memory-only `lib.lua.memo` / `lib.lua.memo.lru` and the
--- sibling `lib.nvim.cache.memory` for callers that need a cache to survive
--- across Neovim restarts. Each namespace is one JSON file under
--- `vim.fn.stdpath("cache") .. "/lib.nvim/cache/<namespace>.json"` by
--- default (override via `opts.dir`), holding `{ saved_at, data }`.
---
--- Usage:
--- ```lua
--- local disk = require("lib.nvim.cache.disk")
---
--- disk.save("github_issues", { { id = 1, title = "..." } })
--- local data = disk.load("github_issues", { ttl_seconds = 3600 })
--- -- data is nil if missing, unreadable, or older than ttl_seconds
---
--- disk.clear("github_issues")
--- local stats = disk.stats("github_issues")
--- ```

local uv = vim.uv or vim.loop

local M = {}

---@internal
---@param opts Lib.Cache.Opts|nil
---@return string
local function cache_dir(opts)
  return (opts and opts.dir) or (vim.fn.stdpath("cache") .. "/lib.nvim/cache")
end

---@internal
---@param namespace string
---@param opts Lib.Cache.Opts|nil
---@return string
local function cache_path(namespace, opts)
  return cache_dir(opts) .. "/" .. namespace .. ".json"
end

---@internal
---Read and JSON-decode the cache file for `namespace`, if any.
---
---A decode failure on non-empty content is not the same situation as no
---file existing at all: every `M.save` call overwrites the WHOLE file, so a
---caller built on top of this module (e.g. `lib.nvim.store.project`, whose
---own docs describe holding curated per-project state like anchors, not
---just regenerable cache entries) can easily have a load-modify-save cycle
---where a decode failure collapses straight to an empty/default in-memory
---value -- and the very next unrelated write then silently replaces the
---corrupt file with that near-empty value, destroying whatever real data
---was in it with no trace it ever existed. The original bytes are backed up
---once per corruption (a `.corrupt` file next to the cache file, not
---re-written if it already exists — so a caller retrying a decode after an
---earlier backup does not clobber it with, say, an even-more-truncated
---read), so "the file was briefly unreadable" never turns into "the data is
---gone". Bug pattern found and fixed the same way three times already
---across the plugin fleet before landing here at the shared root.
---@param namespace string
---@param opts Lib.Cache.Opts|nil
---@return { saved_at: integer, data: any }|nil
local function read_entry(namespace, opts)
  local path = cache_path(namespace, opts)

  local ok_read, content = pcall(function()
    local file = io.open(path, "r")
    if not file then
      return nil
    end
    local text = file:read("*a")
    file:close()
    return text
  end)
  if not ok_read or not content then
    return nil
  end

  local ok_decode, decoded = pcall(vim.json.decode, content)
  if not ok_decode or type(decoded) ~= "table" then
    if content ~= "" then
      local backup_path = path .. ".corrupt"
      if uv.fs_stat(backup_path) == nil then
        local fh = io.open(backup_path, "wb")
        if fh then
          fh:write(content)
          fh:close()
        end
      end
    end
    return nil
  end

  return decoded
end

---Persist `data` under `namespace`.
---@param namespace string
---@param data any
---@param opts? Lib.Cache.SaveOpts
---@return boolean ok
---@return string|nil err
function M.save(namespace, data, opts)
  opts = opts or {}
  local path = cache_path(namespace, opts)

  -- The parent of the *file*, not the cache root. A namespace may contain
  -- slashes to group related entries ("myplugin/anchors" — the form this
  -- module's own callers document), and that subdirectory has to exist or
  -- `io.open(…, "w")` fails with ENOENT. Creating only the cache root left
  -- every nested namespace silently unwritable.
  local dir = vim.fn.fnamemodify(path, ":h")

  local ok_mkdir = pcall(vim.fn.mkdir, dir, "p")
  if not ok_mkdir then
    return false, "mkdir failed: " .. dir
  end

  local entry = { saved_at = os.time(), data = data }
  local ok_encode, encoded = pcall(vim.json.encode, entry)
  if not ok_encode then
    return false, "json encode failed"
  end

  local file, err = io.open(path, "w")
  if not file then
    return false, "open failed: " .. (err or path)
  end
  file:write(encoded)
  file:close()

  return true, nil
end

---Load the cached value for `namespace`, or `nil` if missing, unreadable, or
---expired (per `opts.ttl_seconds`).
---@param namespace string
---@param opts? Lib.Cache.LoadOpts|Lib.Cache.Opts
---@return any|nil data
function M.load(namespace, opts)
  opts = opts or {}
  local entry = read_entry(namespace, opts)
  if not entry then
    return nil
  end

  if opts.ttl_seconds then
    local saved_at = entry.saved_at or 0
    if os.time() - saved_at > opts.ttl_seconds then
      return nil
    end
  end

  return entry.data
end

---Remove the cache file for `namespace`.
---@param namespace string
---@param opts? Lib.Cache.Opts
---@return boolean ok
function M.clear(namespace, opts)
  local path = cache_path(namespace, opts)
  if uv.fs_stat(path) == nil then
    return true
  end
  local ok = os.remove(path)
  return ok ~= nil
end

---Report on-disk state for `namespace` without decoding the full `data` payload.
---@param namespace string
---@param opts? Lib.Cache.Opts
---@return Lib.Cache.Stats
function M.stats(namespace, opts)
  local path = cache_path(namespace, opts)

  local stat = uv.fs_stat(path)
  if not stat then
    return { exists = false, saved_at = nil, age_seconds = nil, size_bytes = nil }
  end

  -- Simplicity over micro-optimization: full-decode to read `saved_at`
  -- rather than hand-parsing the JSON header.
  local entry = read_entry(namespace, opts)
  local saved_at = entry and entry.saved_at or nil

  return {
    exists = true,
    saved_at = saved_at,
    age_seconds = saved_at and (os.time() - saved_at) or nil,
    size_bytes = stat.size,
  }
end

---@type Lib.Cache.Disk
return M
