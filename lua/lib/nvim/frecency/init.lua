---@module 'lib.nvim.frecency'
---Frequency × recency ranking for anything a user picks repeatedly.
---
---Usage: >lua
---
---  local visits = require("lib.nvim.frecency").store({ namespace = "gopath-alternates" })
---  visits:record("/home/me/project/config.lua")   -- the user chose this one
---  local bonus = visits:lookup(candidate_paths)   -- path -> weighted score
---
---The score combines two facts about a key: **how often** it has been chosen
---(log-dampened, so one path picked hundreds of times does not permanently
---own the top of every list) and **how recently** (bucketed, so a visit from
---the last hour counts far more than one from last month). That is the same
---shape of heuristic telescope-frecency and browser address bars use, and it
---is deliberately not a decay curve: buckets are legible in a way an
---exponent is not, and nobody has to reason about a half-life to predict what
---a list will do.
---
---**One handle per namespace, and that is enforced here rather than left to
---each caller.** A store *is* its file. Two handles on the same namespace
---would each hold their own in-memory copy and overwrite the other's on
---flush, losing whichever visits happened to be recorded second — a defect
---that shows up as "my counts sometimes reset", months later, on someone
---else's machine. `store()` therefore returns the same handle for the same
---`dir`/`namespace` pair.
---
---**The weight is an argument, not a property of the store.** It belongs to
---the caller's configuration, which can change while Neovim runs; a store
---handle is cached for the whole session and would have frozen whatever
---weight happened to be configured when it was first opened.
---
---**Nothing here knows what a key means.** File paths, alternate candidates,
---command names — the store ranks strings. That is what lets one
---implementation serve a picker ranking files and a resolver ranking
---alternates, provided they use different namespaces.
---
---Persistence goes through `lib.nvim.cache.disk`, which already owns
---namespaced, `pcall`-guarded JSON with directory creation. The default
---directory is under `stdpath("data")`, not `stdpath("cache")`: these counts
---accumulate over months of real use and cannot be regenerated, which is
---exactly what a cache directory does not promise.

require("lib.nvim.frecency.@types")

local disk = require("lib.nvim.cache.disk")

local M = {}

---Live handles, keyed by `dir .. "/" .. namespace`.
---@type table<string, Lib.Frecency.Store>
local handles = {}

---Bucketed recency weight. A visit from the last hour counts far more than
---one from a month ago, and the last bucket is a floor rather than zero —
---something chosen a year ago is still evidence, just weak evidence.
---@internal
---@param age_seconds number
---@return number
local function recency_weight(age_seconds)
  if age_seconds < 3600 then
    return 100 -- < 1h
  elseif age_seconds < 86400 then
    return 80 -- < 1d
  elseif age_seconds < 604800 then
    return 60 -- < 1w
  elseif age_seconds < 2592000 then
    return 40 -- < 30d
  else
    return 20
  end
end

---@internal
---@return string
local function default_dir()
  return vim.fs.normalize(vim.fn.stdpath("data") .. "/lib.nvim/frecency")
end

---A store handle for `opts.namespace`, creating it on first call and
---returning the same one afterwards.
---@param opts Lib.Frecency.Opts
---@return Lib.Frecency.Store
function M.store(opts)
  opts = opts or {}
  assert(
    type(opts.namespace) == "string" and opts.namespace ~= "",
    "lib.nvim.frecency: opts.namespace is required"
  )

  local namespace = opts.namespace
  local dir =
    vim.fs.normalize((type(opts.dir) == "string" and opts.dir ~= "") and opts.dir or default_dir())
  local id = dir .. "/" .. namespace
  local existing = handles[id]
  if existing then
    return existing
  end

  local disk_opts = { dir = dir }

  ---@type table<string, Lib.Frecency.Entry>|nil
  local cached = nil
  local dirty = false

  ---The entry table, read from disk on the first call that needs it. A store
  ---that is opened but never used costs nothing, and returning the table
  ---rather than assigning an upvalue keeps every caller free of a nil check
  ---for a value that cannot be nil once this has run.
  ---@internal
  ---@return table<string, Lib.Frecency.Entry>
  local function entries()
    if not cached then
      local loaded = disk.load(namespace, disk_opts)
      cached = type(loaded) == "table" and loaded or {}
    end
    return cached
  end

  ---@type Lib.Frecency.Store
  local store
  store = {
    namespace = namespace,

    ---@param key string
    record = function(_, key)
      if type(key) ~= "string" or key == "" then
        return
      end
      local all = entries()
      local entry = all[key] or { count = 0, last = 0 }
      entry.count = entry.count + 1
      entry.last = os.time()
      all[key] = entry
      dirty = true
    end,

    ---@param key string
    ---@return number
    score = function(_, key)
      if type(key) ~= "string" or key == "" then
        return 0
      end
      local entry = entries()[key]
      if not entry then
        return 0
      end
      return math.log((entry.count or 0) + 1) * recency_weight(os.time() - (entry.last or 0))
    end,

    ---@param keys string[]
    ---@param weight? number
    ---@return table<string, number>
    lookup = function(self, keys, weight)
      local factor = tonumber(weight) or 1.0
      local out = {}
      for _, key in ipairs(keys or {}) do
        local s = self:score(key)
        -- Only what actually scores: a table full of zeroes says the same
        -- thing as an absent key and makes every consumer test for both.
        if s > 0 then
          out[key] = s * factor
        end
      end
      return out
    end,

    ---@param incoming table<string, Lib.Frecency.Entry>
    ---@return boolean seeded
    seed = function(_, incoming)
      if type(incoming) ~= "table" then
        return false
      end
      local all = entries()
      -- Never over an existing store. A seed is for adopting counts from
      -- somewhere else -- a store this module did not write, a plugin's own
      -- pre-extraction format -- and adopting them *over* real history would
      -- turn a one-time migration into silent data loss the second time it
      -- ran.
      if next(all) ~= nil then
        return false
      end
      local taken = 0
      for key, entry in pairs(incoming) do
        if
          type(key) == "string"
          and key ~= ""
          and type(entry) == "table"
          and type(entry.count) == "number"
          and type(entry.last) == "number"
        then
          -- Copied field by field rather than by reference: the caller's
          -- table came from somewhere this module does not control, and a
          -- stray extra field would end up serialised into the store.
          all[key] = { count = entry.count, last = entry.last }
          taken = taken + 1
        end
      end
      if taken > 0 then
        dirty = true
      end
      return taken > 0
    end,

    flush = function()
      if not dirty then
        return
      end
      -- An empty table is worth writing: it is the state after `clear`, and
      -- skipping it would resurrect the old file on the next load.
      disk.save(namespace, entries(), disk_opts)
      dirty = false
    end,

    clear = function()
      cached = {}
      dirty = false
      disk.clear(namespace, disk_opts)
    end,

    reset = function()
      cached = nil
      dirty = false
    end,
  }

  if opts.autoflush ~= false then
    local ok, autocmd = pcall(require, "lib.nvim.bindings.autocmd")
    local function on_leave()
      store:flush()
    end
    if ok and type(autocmd) == "table" and type(autocmd.create) == "function" then
      autocmd.create("VimLeavePre", on_leave, {
        group = "lib.nvim.frecency",
        desc = "lib.nvim.frecency: persist '" .. namespace .. "' visits",
      })
    else
      -- lib-docs: fallback
      vim.api.nvim_create_autocmd("VimLeavePre", { callback = on_leave })
    end
  end

  handles[id] = store
  return store
end

---Test-only: forget every live handle, so the next `store()` builds a fresh
---one. Touches nothing on disk — a spec that wants the file gone calls
---`clear()` on the handle first.
function M._reset_handles()
  handles = {}
end

---@type Lib.Frecency
return M
