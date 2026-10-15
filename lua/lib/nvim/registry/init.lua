---@module 'lib.nvim.registry'
--- A generic registry: who is responsible for X, self-registration, deterministic order, `reset()` for tests.
---
--- The pattern turns up everywhere a plugin has "one entry per language / verb / backend / renderer": a name
--- (or any key) maps to a value, entries register themselves (a backend module calls `register` when it is
--- required), lookups are answered in **registration order** (never `pairs()` order, so a scan or a generated
--- doc is the same on every run), and a test can start from an empty one.
---
--- Extracted from `documentation.nvim`'s `lang_registry` and `usercmd.composer.registry`. Domain rules stay
--- with the owner (which backend claims a file name, a scan-scoped filter ...): this holds the entries.
---
--- ```lua
--- local registry = require("lib.nvim.registry")
---
--- local langs = registry.new({
---   name = "lang",
---   validate = function(key, backend)
---     return type(backend.is_source) == "function", "a backend needs is_source()"
---   end,
---   -- run once, before the first read: the one place that names the backend modules
---   loader = function()
---     require("my.lang.lua")
---     require("my.lang.python")
---   end,
--- })
---
--- langs:register("lua", { is_source = function(f) return f:match("%.lua$") ~= nil end })
--- langs:get("lua")
--- langs:find(function(key, backend) return backend.is_source("a.lua") end)  --> "lua", backend
--- langs:keys()      --> { "lua", "python" } (registration order)
--- langs:reset()     -- tests: empty again; the loader runs again before the next read
--- ```

local M = {}

---@class Lib.Registry.Opts
---@field name? string                                       # Used in messages (default "registry").
---@field validate? fun(key: any, value: any): boolean?, string?  # Refuse a registration: return false/nil (+ reason).
---@field loader? fun()                                      # Runs once before the first read (and again after `reset`).
---@field on_duplicate? "replace"|"keep"|"error"             # Same key twice (default "replace", keeping its position).

---@class Lib.Registry
---@field private _name string
---@field private _order any[]
---@field private _values table
---@field private _validate? function
---@field private _loader? function
---@field private _loaded boolean
---@field private _failed boolean    # The last loader run threw.
---@field private _retrying boolean  # The loader is running again after a failed run.
---@field private _on_duplicate string
local Registry = {}
Registry.__index = Registry

---Run the loader once. Marked loaded BEFORE it runs: a loader module that registers itself by calling
---back into this registry (the usual shape) must not recurse into the loader again.
---@private
function Registry:_ensure()
  if self._loaded then
    return
  end
  self._loaded = true
  if self._loader then
    -- the run after a failed one registers the same keys again: that is not a duplicate
    local retry = self._failed
    self._retrying = retry
    local ok, err = pcall(self._loader)
    self._retrying = false
    if not ok then
      -- not "loaded": the next read runs it again instead of serving a half-filled registry in silence
      self._loaded = false
      self._failed = true
      error(err, 0)
    end
    self._failed = false
  end
end

---Register `value` under `key`. Returns the registry (chainable).
---
---A key registered twice follows `on_duplicate`: `"replace"` (default) swaps the value and keeps the
---position, `"keep"` leaves the first one, `"error"` raises.
---@param key any   # Not nil.
---@param value any # Not nil.
---@return Lib.Registry
function Registry:register(key, value)
  if key == nil or value == nil then
    error(("lib.nvim.registry (%s): key and value must not be nil"):format(self._name), 2)
  end
  if self._validate then
    local ok, valid, why = pcall(self._validate, key, value)
    if not ok then
      error(
        ("lib.nvim.registry (%s): validate raised for %s: %s"):format(
          self._name,
          tostring(key),
          tostring(valid)
        ),
        2
      )
    end
    if not valid then
      error(
        ("lib.nvim.registry (%s): refused %s%s"):format(
          self._name,
          tostring(key),
          why and (": " .. tostring(why)) or ""
        ),
        2
      )
    end
  end
  if self._values[key] ~= nil then
    if self._on_duplicate == "error" and not self._retrying then
      error(
        ("lib.nvim.registry (%s): %s is already registered"):format(self._name, tostring(key)),
        2
      )
    elseif self._on_duplicate == "keep" then
      return self
    end
  else
    self._order[#self._order + 1] = key
  end
  self._values[key] = value
  return self
end

---Remove one entry. Returns whether there was one.
---@param key any
---@return boolean
function Registry:unregister(key)
  self:_ensure()
  if self._values[key] == nil then
    return false
  end
  self._values[key] = nil
  for i, k in ipairs(self._order) do
    if k == key then
      table.remove(self._order, i)
      break
    end
  end
  return true
end

---@param key any
---@return any|nil
function Registry:get(key)
  self:_ensure()
  return self._values[key]
end

---@param key any
---@return boolean
function Registry:has(key)
  self:_ensure()
  return self._values[key] ~= nil
end

---@return integer
function Registry:count()
  self:_ensure()
  return #self._order
end

---The keys, in registration order (a fresh list).
---@return any[]
function Registry:keys()
  self:_ensure()
  return vim.list_extend({}, self._order)
end

---The values, in registration order (a fresh list). With `pred`, only those it accepts.
---@param pred? fun(key: any, value: any): boolean?
---@return any[]
function Registry:all(pred)
  self:_ensure()
  local out = {}
  for _, key in ipairs(self._order) do
    local value = self._values[key]
    if pred == nil or pred(key, value) then
      out[#out + 1] = value
    end
  end
  return out
end

---`{ key, value }` pairs in registration order (a fresh list).
---@return { [1]: any, [2]: any }[]
function Registry:entries()
  self:_ensure()
  local out = {}
  for _, key in ipairs(self._order) do
    out[#out + 1] = { key, self._values[key] }
  end
  return out
end

---The first entry (in registration order) `pred` accepts: who is responsible.
---@param pred fun(key: any, value: any): boolean?
---@return any|nil key
---@return any|nil value
function Registry:find(pred)
  self:_ensure()
  for _, key in ipairs(self._order) do
    local value = self._values[key]
    if pred(key, value) then
      return key, value
    end
  end
  return nil, nil
end

---Drop every entry. The loader (if any) runs again before the next read, so a test starts empty and a
---later read finds the known entries again.
---@return Lib.Registry
function Registry:reset()
  self._order = {}
  self._values = {}
  self._loaded = false
  self._failed = false
  return self
end

---A new, empty registry.
---@param opts? Lib.Registry.Opts
---@return Lib.Registry
function M.new(opts)
  opts = opts or {}
  local dup = opts.on_duplicate or "replace"
  if dup ~= "replace" and dup ~= "keep" and dup ~= "error" then
    error('lib.nvim.registry.new: on_duplicate must be "replace", "keep" or "error"', 2)
  end
  return setmetatable({
    _name = opts.name or "registry",
    _order = {},
    _values = {},
    _validate = opts.validate,
    _loader = opts.loader,
    _loaded = false,
    _on_duplicate = dup,
  }, Registry)
end

return M
