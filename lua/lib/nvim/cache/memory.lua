---@module 'lib.nvim.cache.memory'
--- Generic in-memory cache namespaces for event handlers: per-key TTL and/or
--- buffer-changedtick validation, hit/miss/eviction stats, and an opt-in
--- autocmd-driven auto-invalidation sweep.
---
--- Complements the persistent `lib.nvim.cache.disk` (this cache does not
--- survive a restart) and `lib.lua.memo`/`lib.lua.memo.lru` (which memoize a
--- single function rather than holding an arbitrary key/value namespace).
---
---   local memory = require("lib.nvim.cache.memory")
---   local ns = memory.namespace("my_plugin.something", { ttl = 5 })
---
---   local value = ns.get(key, bufnr)      -- nil if missing/expired/stale tick
---   if not value then
---     value = expensive_compute()
---     ns.set(key, value, bufnr)           -- bufnr enables tick invalidation
---   end
---
--- Namespaces are pure and always available; nothing global is touched until
--- a caller opts in:
---
---   memory.setup_auto_invalidation()      -- install the sweep autocmds
---   memory.disable_auto_invalidation()    -- and remove them again (toggle)

local autocmd = require("lib.nvim.autocmd")

local api = vim.api
local uv = vim.uv or vim.loop
local nvim_buf_get_changedtick = api.nvim_buf_get_changedtick

--- Monotonic clock in seconds. `os.clock()` measures CPU time, not wall time,
--- so a TTL built on it would barely advance while Neovim sits idle; `hrtime`
--- is wall-clock-accurate and immune to system clock adjustments.
---@return number
local function now()
  return uv.hrtime() / 1e9
end

local M = {}

--- Backing store per namespace name, keyed weakly so an abandoned namespace
--- (caller drops its reference and never calls it again) can still be
--- garbage-collected along with its entries.
---@type table<string, table>
local caches = setmetatable({}, { __mode = "k" })

---@type table<string, Lib.Cache.Memory.Stats>
local stats = {}

--- Create or get a cache namespace. Repeated calls with the same `name`
--- share one backing store, so unrelated callers can cheaply agree on a
--- namespace by name instead of having to pass a table reference around.
---@param name string
---@param opts? Lib.Cache.Memory.NamespaceOpts
---@return Lib.Cache.Memory.Namespace
function M.namespace(name, opts)
  opts = opts or {}

  if not caches[name] then
    caches[name] = setmetatable({}, { __mode = "k" })
    stats[name] = {
      name = name,
      hits = 0,
      misses = 0,
      invalidations = 0,
      evictions = 0,
      total_requests = 0,
      hit_rate = 0,
    }
  end

  local cache = caches[name]
  local ns_stats = stats[name]

  return {
    get = function(key, bufnr)
      local entry = cache[key]
      if not entry then
        ns_stats.misses = ns_stats.misses + 1
        return nil
      end

      if opts.ttl and entry.ttl then
        if now() - entry.timestamp > entry.ttl then
          cache[key] = nil
          ns_stats.evictions = ns_stats.evictions + 1
          ns_stats.misses = ns_stats.misses + 1
          return nil
        end
      end

      if bufnr and entry.tick then
        if nvim_buf_get_changedtick(bufnr) ~= entry.tick then
          cache[key] = nil
          ns_stats.evictions = ns_stats.evictions + 1
          ns_stats.misses = ns_stats.misses + 1
          return nil
        end
      end

      ns_stats.hits = ns_stats.hits + 1
      return entry.value
    end,

    set = function(key, value, bufnr)
      local entry = { value = value, timestamp = now(), ttl = opts.ttl }
      if bufnr then
        entry.tick = nvim_buf_get_changedtick(bufnr)
      end
      cache[key] = entry
    end,

    invalidate = function(key)
      if cache[key] then
        cache[key] = nil
        ns_stats.invalidations = ns_stats.invalidations + 1
      end
    end,

    clear = function()
      -- Clear in place (not `caches[name] = setmetatable({}, ...)`): a
      -- wholesale table replacement would only be visible through *this*
      -- closure's `cache` upvalue, silently orphaning any other accessor
      -- obtained from an earlier/later `M.namespace(name)` call for the same
      -- name — including the auto-invalidation sweep, which only ever
      -- touches the `caches` table, never a namespace's private upvalue.
      local count = 0
      for key in pairs(cache) do
        cache[key] = nil
        count = count + 1
      end
      ns_stats.invalidations = ns_stats.invalidations + count
    end,

    stats = function()
      local total = ns_stats.hits + ns_stats.misses
      return {
        name = name,
        hits = ns_stats.hits,
        misses = ns_stats.misses,
        invalidations = ns_stats.invalidations,
        evictions = ns_stats.evictions,
        total_requests = total,
        hit_rate = total > 0 and (ns_stats.hits / total * 100) or 0,
      }
    end,
  }
end

--- Augroup name currently holding the auto-invalidation autocmds, or nil.
---@type string|nil
local auto_group_name = nil

--- Opt-in: install autocmds that keep every namespace tidy without callers
--- having to invalidate manually.
---   * `TextChanged`/`TextChangedI` — prune entries whose bound tick no
---     longer matches the edited buffer.
---   * `BufWritePost` — clear every namespace outright.
--- Idempotent: safe to call repeatedly (e.g. from a config reload) — the
--- augroup is created with `clear = true`, so autocmds never accumulate.
--- Calling with a different `opts.prefix` moves the sweep to the new
--- augroup name; the previous one is removed first.
---@param opts? Lib.Cache.Memory.AutoInvalidationOpts
function M.setup_auto_invalidation(opts)
  opts = opts or {}
  local name = opts.prefix or "lib.nvim.cache.memory"

  if auto_group_name and auto_group_name ~= name then
    pcall(api.nvim_del_augroup_by_name, auto_group_name)
  end
  auto_group_name = name

  -- `nvim_create_augroup(..., { clear = true })` always wipes and rebuilds
  -- the group, which is what makes this whole function idempotent; going
  -- through `lib.nvim.autocmd.group` instead would cache the id after the
  -- first call and silently skip the clear on later calls.
  local group = api.nvim_create_augroup(name, { clear = true })

  autocmd.create({ "TextChanged", "TextChangedI" }, function(ev)
    for ns_name, cache in pairs(caches) do
      local invalidated = 0
      for key, entry in pairs(cache) do
        if entry.tick and api.nvim_buf_is_valid(ev.buf) then
          if entry.tick ~= nvim_buf_get_changedtick(ev.buf) then
            cache[key] = nil
            invalidated = invalidated + 1
          end
        end
      end
      if invalidated > 0 and stats[ns_name] then
        stats[ns_name].invalidations = stats[ns_name].invalidations + invalidated
      end
    end
  end, { group = group, desc = "lib.nvim.cache.memory: prune stale tick-bound entries" })

  autocmd.create("BufWritePost", function()
    -- In-place clear, same reasoning as the namespace's own `clear()`: it
    -- must stay visible to every accessor sharing this namespace's table.
    for _, cache in pairs(caches) do
      for key in pairs(cache) do
        cache[key] = nil
      end
    end
  end, { group = group, desc = "lib.nvim.cache.memory: clear all namespaces on write" })
end

--- Toggle off: remove the augroup installed by `setup_auto_invalidation`.
--- No-op if auto-invalidation was never enabled.
function M.disable_auto_invalidation()
  if not auto_group_name then
    return
  end
  pcall(api.nvim_del_augroup_by_name, auto_group_name)
  auto_group_name = nil
end

---@return boolean
function M.is_auto_invalidation_enabled()
  return auto_group_name ~= nil
end

--- Snapshot of every namespace's stats, in no particular order.
---@return Lib.Cache.Memory.Stats[]
function M.get_all_stats()
  local all = {}
  for name in pairs(caches) do
    local s = stats[name]
    local total = s.hits + s.misses
    all[#all + 1] = {
      name = name,
      hits = s.hits,
      misses = s.misses,
      invalidations = s.invalidations,
      evictions = s.evictions,
      total_requests = total,
      hit_rate = total > 0 and (s.hits / total * 100) or 0,
    }
  end
  return all
end

--- `print()` a formatted table of every namespace's stats; debugging aid.
function M.print_all_stats()
  local all = M.get_all_stats()

  print("Cache Statistics:")
  print(string.format(
    "%-30s %8s %8s %8s %8s %10s",
    "Namespace", "Hits", "Misses", "Invalid", "Evict", "Hit Rate"
  ))
  print(string.rep("-", 80))

  for _, s in ipairs(all) do
    print(string.format(
      "%-30s %8d %8d %8d %8d %9.2f%%",
      s.name, s.hits, s.misses, s.invalidations, s.evictions, s.hit_rate
    ))
  end
end

---@type Lib.Cache.Memory
return M
