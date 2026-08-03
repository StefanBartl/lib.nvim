---@module 'lib.nvim.telemetry.store'
--- Persistence for telemetry counters, on top of `lib.nvim.cache.disk`.
---
--- Two things this file exists to get right:
---
--- 1. **Merge-on-write, not last-write-wins.** Counts are per-process, and two
---    Neovim instances sharing a namespace would otherwise overwrite each
---    other's totals. Every flush re-reads what is on disk and adds only the
---    delta collected since the previous flush.
--- 2. **Namespace sanitization.** `cache.disk` builds its path as
---    `dir .. "/" .. namespace .. ".json"` with no escaping, and a namespace is
---    a plugin-chosen string. `"../../evil"` would write outside the cache
---    directory. Sanitizing here is cheap; changing `cache.disk` would be a
---    wider change affecting every existing caller.

local disk = require("lib.nvim.cache.disk")

local M = {}

M.VERSION = 1

--- Everything but these is replaced with `_`. Slashes included: `cache.disk`
--- supports nested namespaces, but a telemetry namespace is a plugin name, and
--- allowing separators is exactly how `..` escapes the cache directory.
local SAFE = "[^%w%-%._]"

---@param namespace string
---@return string
function M.sanitize(namespace)
  local s = tostring(namespace or ""):gsub(SAFE, "_")
  -- A name of only dots still resolves relative to the cache dir.
  s = s:gsub("^%.+", "")
  if s == "" then
    s = "unnamed"
  end
  return s
end

---@param namespace string
---@return string
function M.cache_key(namespace)
  return "telemetry/" .. M.sanitize(namespace)
end

---@return string  # "YYYY-MM-DD" in local time
function M.today()
  return os.date("%Y-%m-%d") --[[@as string]]
end

---An empty, well-formed data table.
---@return Lib.Telemetry.Data
function M.empty()
  return {
    version = M.VERSION,
    started_at = os.time(),
    sessions = 0,
    functions = {},
    days = {},
    reminded = {},
    modules = {},
    info = {},
  }
end

---Normalize whatever came back from disk into the current shape.
---@param raw any
---@return Lib.Telemetry.Data
local function normalize(raw)
  if type(raw) ~= "table" or raw.version ~= M.VERSION then
    return M.empty()
  end
  raw.functions = type(raw.functions) == "table" and raw.functions or {}
  raw.days = type(raw.days) == "table" and raw.days or {}
  raw.reminded = type(raw.reminded) == "table" and raw.reminded or {}
  raw.sessions = tonumber(raw.sessions) or 0
  raw.started_at = tonumber(raw.started_at) or os.time()
  -- Added after version 1 shipped; older cache files simply lack it. Purely
  -- additive, so this does not warrant a version bump — a missing map and an
  -- empty one mean the same thing to every reader.
  raw.modules = type(raw.modules) == "table" and raw.modules or {}
  raw.info = type(raw.info) == "table" and raw.info or {}
  return raw
end

---@param namespace string
---@param opts? Lib.Cache.Opts
---@return Lib.Telemetry.Data
function M.load(namespace, opts)
  local ok, raw = pcall(disk.load, M.cache_key(namespace), opts)
  return normalize(ok and raw or nil)
end

---Like `load`, but distinguishes "nothing was ever persisted" from "persisted
---and empty" — returns `nil` rather than a well-formed empty table when no
---cache entry exists for `namespace`.
---
---`load()` collapses that distinction on purpose: a live instance's `base`
---always wants *something* to merge into, and "never flushed before" and
---"flushed, zero counts" are the same starting point for it. A caller reading
---a namespace it does not own — no live instance, possibly never enabled
---here at all — needs to tell those apart, or "no data" renders as a
---graveyard instead of "no data". See `telemetry.load()`.
---@param namespace string
---@param opts? Lib.Cache.Opts
---@return Lib.Telemetry.Data|nil
function M.load_readonly(namespace, opts)
  local ok, raw = pcall(disk.load, M.cache_key(namespace), opts)
  if not ok or raw == nil then
    return nil
  end
  return normalize(raw)
end

---@param namespace string
---@param data Lib.Telemetry.Data
---@param opts? Lib.Cache.Opts
---@return boolean ok
function M.save(namespace, data, opts)
  local ok, saved = pcall(disk.save, M.cache_key(namespace), data, opts)
  return ok and saved == true
end

---@param namespace string
---@param opts? Lib.Cache.Opts
---@return boolean ok
function M.clear(namespace, opts)
  local ok, cleared = pcall(disk.clear, M.cache_key(namespace), opts)
  return ok and cleared ~= false
end

-- ---------------------------------------------------------------------------
-- Merging
-- ---------------------------------------------------------------------------

---@param dst Lib.Telemetry.ArgStats
---@param src Lib.Telemetry.ArgStats
---@param max_values integer
local function merge_args(dst, src, max_values)
  dst.values = dst.values or {}
  dst.other = dst.other or 0
  dst.distinct = dst.distinct or 0
  dst.n = dst.n or M.count_keys(dst.values)

  local src_values = src.values or {}

  for fp, n in pairs(src_values) do
    if dst.values[fp] then
      dst.values[fp] = dst.values[fp] + n
    else
      -- Bounded cardinality. Without this the stored size is a function of
      -- user data — a function called with 10 000 distinct paths would cost
      -- 10 000 entries, and telemetry becomes the performance problem it was
      -- written to find.
      dst.distinct = dst.distinct + 1
      if dst.n < max_values then
        dst.values[fp] = n
        dst.n = dst.n + 1
      else
        dst.other = dst.other + n
      end
    end
  end

  -- Fingerprints `src` already evicted into its own `other` bucket are gone as
  -- values but still happened, so their contribution to `distinct` has to be
  -- carried over explicitly. Overlap with `dst` is unknowable once a
  -- fingerprint is dropped — this over-counts rather than silently
  -- under-reporting how varied the arguments were.
  dst.distinct = dst.distinct + math.max(0, (src.distinct or 0) - M.count_keys(src_values))
  dst.other = dst.other + (src.other or 0)
end

---@param t table
---@return integer
function M.count_keys(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n
end

---@param dst Lib.Telemetry.Timing
---@param src Lib.Telemetry.Timing
local function merge_timing(dst, src)
  dst.n = (dst.n or 0) + (src.n or 0)
  dst.total_ms = (dst.total_ms or 0) + (src.total_ms or 0)
  dst.min_ms = math.min(dst.min_ms or math.huge, src.min_ms or math.huge)
  dst.max_ms = math.max(dst.max_ms or 0, src.max_ms or 0)
end

---Add `delta` into `base`, in place. Both are `Lib.Telemetry.Data`-shaped;
---`delta` typically holds only what one process collected since its last flush.
---@param base Lib.Telemetry.Data
---@param delta Lib.Telemetry.Data
---@param max_values integer
---@return Lib.Telemetry.Data base
function M.merge(base, delta, max_values)
  for key, src in pairs(delta.functions or {}) do
    local dst = base.functions[key]
    if not dst then
      dst = { calls = 0 }
      base.functions[key] = dst
    end
    dst.calls = (dst.calls or 0) + (src.calls or 0)
    if src.errors then
      dst.errors = (dst.errors or 0) + src.errors
    end
    if src.timing then
      dst.timing = dst.timing or {}
      merge_timing(dst.timing, src.timing)
    end
    if src.args then
      dst.args = dst.args or {}
      merge_args(dst.args, src.args, max_values)
    end
  end

  for day, keys in pairs(delta.days or {}) do
    local dst_day = base.days[day]
    if not dst_day then
      dst_day = {}
      base.days[day] = dst_day
    end
    for key, n in pairs(keys) do
      dst_day[key] = (dst_day[key] or 0) + n
    end
  end

  base.sessions = (base.sessions or 0) + (delta.sessions or 0)
  if delta.started_at and delta.started_at < (base.started_at or math.huge) then
    base.started_at = delta.started_at
  end
  for k, v in pairs(delta.reminded or {}) do
    base.reminded[k] = v
  end

  -- Structural, not a count: which key resolves to which real Lua module
  -- path. Stable across sessions by construction (derived from
  -- `package.loaded`), so last-write-wins is equivalent to first-write-wins
  -- here -- there is no meaningful "older" value to preserve.
  base.modules = base.modules or {}
  for key, module_id in pairs(delta.modules or {}) do
    base.modules[key] = module_id
  end

  -- Unlike `modules`, genuinely last-write-wins, not merely equivalent to
  -- it: a branch/version can change between sessions (an upgrade, a
  -- `git checkout`), and the newer session's `info` describes the state
  -- that produced the calls just merged in, not a blend of two states that
  -- were never simultaneously true. Replaced wholesale rather than
  -- key-by-key so a caller who stops setting a field (switches to a
  -- narrower `info` table) does not leave a stale one behind forever.
  if delta.info and next(delta.info) ~= nil then
    base.info = delta.info
  else
    base.info = base.info or {}
  end

  return base
end

---Drop day buckets older than `days`. Bounded growth is the whole reason for
---day keys; without a prune step they are just a slower leak.
---@param data Lib.Telemetry.Data
---@param days integer
---@return integer dropped
function M.prune(data, days)
  if not days or days <= 0 then
    return 0
  end
  local cutoff = os.date("%Y-%m-%d", os.time() - days * 86400)
  local dropped = 0
  for day in pairs(data.days or {}) do
    if day < cutoff then
      data.days[day] = nil
      dropped = dropped + 1
    end
  end
  return dropped
end

---Sum the day buckets covering the last `days` days.
---@param data Lib.Telemetry.Data
---@param days integer
---@return table<string, integer> calls_by_key
---@return integer total
function M.since(data, days)
  local cutoff = os.date("%Y-%m-%d", os.time() - days * 86400)
  local out, total = {}, 0
  for day, keys in pairs(data.days or {}) do
    if day >= cutoff then
      for key, n in pairs(keys) do
        out[key] = (out[key] or 0) + n
        total = total + n
      end
    end
  end
  return out, total
end

---Parse `"7d"` / `"24h"` / `7` into a day count.
---@param since string|integer|nil
---@return integer|nil
function M.parse_since(since)
  if since == nil then
    return nil
  end
  if type(since) == "number" then
    return math.max(1, math.floor(since))
  end
  local n, unit = tostring(since):match("^(%d+)%s*(%a?)")
  if not n then
    return nil
  end
  n = tonumber(n)
  if unit == "h" then
    return math.max(1, math.ceil(n / 24))
  end
  if unit == "w" then
    return n * 7
  end
  return math.max(1, n)
end

return M
