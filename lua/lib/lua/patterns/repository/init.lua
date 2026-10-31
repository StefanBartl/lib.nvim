---@module 'lib.lua.patterns.repository'
--- Repository: hide storage behind a collection-like API.
---
--- A repository sits on a store with four primitives: `get(id)`, `put(id, value)`, `delete(id)` and
--- `all()` (a list of `{ id, value }` entries, in a stable order). Code works with `get`, `save`, `remove`,
--- `find(predicate)`, `count()`; where the data lives (a table, a JSON file, `lib.nvim.store`) is the
--- store's business. `repository.memory()` is an in-memory store for tests and small cases.
---
--- ```lua
--- local repository = require("lib.lua.patterns.repository")
--- local users = repository.new(repository.memory())
--- users:save("u1", { name = "Ada" })
--- users:find(function(u) return u.name == "Ada" end) --> { id = "u1", value = {...} }
--- ```
---
--- Status: idea pool. Worth it when the storage is likely to change or must be faked in tests; for one
--- JSON file a pair of read/write functions is simpler.

require("lib.lua.patterns.repository.@types")

local M = {}

---An in-memory store.
---@return Lib.Patterns.Store
function M.memory()
  local data, order = {}, {}
  return {
    get = function(id)
      return data[id]
    end,
    put = function(id, value)
      if data[id] == nil then
        order[#order + 1] = id
      end
      data[id] = value
    end,
    delete = function(id)
      if data[id] ~= nil then
        data[id] = nil
        for i, k in ipairs(order) do
          if k == id then
            table.remove(order, i)
            break
          end
        end
      end
    end,
    all = function()
      local out = {}
      for i, id in ipairs(order) do
        out[i] = { id = id, value = data[id] }
      end
      return out
    end,
  }
end

---@class Lib.Patterns.Repository
local R = {}
R.__index = R

---@param store Lib.Patterns.Store
---@return Lib.Patterns.Repository
function M.new(store)
  for _, name in ipairs({ "get", "put", "delete", "all" }) do
    if type(store[name]) ~= "function" then
      error(("repository.new: store lacks %q"):format(name), 2)
    end
  end
  return setmetatable({ store = store }, R)
end

---@param id any
---@return any
function R:get(id)
  return self.store.get(id)
end

---@param id any
---@param value any
function R:save(id, value)
  if value == nil then
    error("repository.save: value must not be nil (use remove)", 2)
  end
  self.store.put(id, value)
end

---@param id any
function R:remove(id)
  self.store.delete(id)
end

---@return { id: any, value: any }[]
function R:all()
  return self.store.all()
end

---First entry whose value satisfies `predicate`.
---@param predicate fun(value: any, id: any): boolean
---@return { id: any, value: any }|nil
function R:find(predicate)
  for _, e in ipairs(self.store.all()) do
    if predicate(e.value, e.id) then
      return e
    end
  end
  return nil
end

---All entries whose value satisfies `predicate`.
---@param predicate fun(value: any, id: any): boolean
---@return { id: any, value: any }[]
function R:filter(predicate)
  local out = {}
  for _, e in ipairs(self.store.all()) do
    if predicate(e.value, e.id) then
      out[#out + 1] = e
    end
  end
  return out
end

---@return integer
function R:count()
  return #self.store.all()
end

return M
