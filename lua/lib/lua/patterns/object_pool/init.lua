---@module 'lib.lua.patterns.object_pool'
--- Object pool: reuse expensive objects (scratch tables, timers, buffers) instead of creating and
--- dropping them. `acquire()` hands out a free object or creates one, `release(obj)` resets it and keeps
--- it for the next caller, up to `max` idle objects.
---
--- ```lua
--- local pool = require("lib.lua.patterns.object_pool").new({
---   create = function() return {} end,
---   reset = function(t) for k in pairs(t) do t[k] = nil end end,
---   max = 8,
--- })
--- pool:with(function(t) t.x = 1 end)
--- ```
---
--- Worth it only for objects that are costly to create. Lua tables are cheap; measure first.

require("lib.lua.patterns.object_pool.@types")

local M = {}

local unpack = table.unpack or unpack

---`table.pack` is missing on plain LuaJIT.
local function pack(...)
  return { n = select("#", ...), ... }
end

---@class Lib.Patterns.ObjectPool
local P = {}
P.__index = P

---@param opts Lib.Patterns.ObjectPool.Opts
---@return Lib.Patterns.ObjectPool
function M.new(opts)
  if type(opts) ~= "table" or type(opts.create) ~= "function" then
    error("object_pool.new: opts.create (function) is required", 2)
  end
  return setmetatable({
    create = opts.create,
    reset = opts.reset,
    destroy = opts.destroy,
    max = opts.max or 16,
    idle = {},
    created = 0,
    reused = 0,
  }, P)
end

---@return any
function P:acquire()
  local obj = table.remove(self.idle)
  if obj ~= nil then
    self.reused = self.reused + 1
    return obj
  end
  self.created = self.created + 1
  return self.create()
end

---Return an object. It is reset and kept if there is room, otherwise destroyed.
---@param obj any
function P:release(obj)
  if obj == nil then
    return
  end
  if #self.idle >= self.max then
    if self.destroy then
      pcall(self.destroy, obj)
    end
    return
  end
  if self.reset then
    local ok = pcall(self.reset, obj)
    if not ok then
      if self.destroy then
        pcall(self.destroy, obj)
      end
      return
    end
  end
  self.idle[#self.idle + 1] = obj
end

---Acquire, run `fn(obj)`, release even if `fn` raises (the error is re-raised after the release).
---@param fn fun(obj: any): ...
---@return ...
function P:with(fn)
  local obj = self:acquire()
  local res = pack(pcall(fn, obj))
  self:release(obj)
  if not res[1] then
    error(res[2], 0)
  end
  return unpack(res, 2, res.n)
end

---Destroy every idle object.
function P:clear()
  if self.destroy then
    for _, obj in ipairs(self.idle) do
      pcall(self.destroy, obj)
    end
  end
  self.idle = {}
end

---@return { idle: integer, created: integer, reused: integer }
function P:stats()
  return { idle = #self.idle, created = self.created, reused = self.reused }
end

return M
