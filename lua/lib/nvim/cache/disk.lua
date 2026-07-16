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

---@param opts Lib.Cache.Opts|nil
---@return string
local function cache_dir(opts)
  return (opts and opts.dir) or (vim.fn.stdpath("cache") .. "/lib.nvim/cache")
end

---@param namespace string
---@param opts Lib.Cache.Opts|nil
---@return string
local function cache_path(namespace, opts)
  return cache_dir(opts) .. "/" .. namespace .. ".json"
end

---Read and JSON-decode the cache file for `namespace`, if any.
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
  local dir = cache_dir(opts)

  local ok_mkdir = pcall(vim.fn.mkdir, dir, "p")
  if not ok_mkdir then
    return false, "mkdir failed: " .. dir
  end

  local entry = { saved_at = os.time(), data = data }
  local ok_encode, encoded = pcall(vim.json.encode, entry)
  if not ok_encode then
    return false, "json encode failed"
  end

  local path = cache_path(namespace, opts)
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
---@param opts? Lib.Cache.LoadOpts
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
