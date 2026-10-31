---@module 'lib.lua.patterns.flyweight'
--- Flyweight: share identical immutable objects instead of creating one per use.
---
--- `get(...)` returns the shared instance for a key; the factory runs once per key. The key defaults to
--- the arguments joined by a separator; pass `opts.key` for anything else. With `opts.weak = true` the
--- cache holds its values weakly, so an instance no longer used elsewhere can be collected.
---
--- ```lua
--- local flyweight = require("lib.lua.patterns.flyweight")
--- local hl = flyweight.new(function(fg, bg) return { fg = fg, bg = bg } end)
--- hl:get("red", "black") == hl:get("red", "black") --> true
--- ```
---
--- Status: idea pool. It saves memory only when very many equal objects exist. The shared object must
--- not be mutated by its users.

require("lib.lua.patterns.flyweight.@types")

local M = {}

---@class Lib.Patterns.Flyweight
local F = {}
F.__index = F

local IDENTITY = { table = true, ["function"] = true, userdata = true, thread = true }

---One key builder per flyweight: reference arguments (tables, functions, ...) are keyed by a unique
---counter held in a weak-keyed table, never by `tostring` (an address that is reused after a collection).
local function make_default_key()
  local ids, next_id = setmetatable({}, { __mode = "k" }), 0
  return function(...)
    local parts = {}
    for i = 1, select("#", ...) do
      -- type tag and length prefix: get(1) and get("1"), get(nil) and get("nil"), get("a\31b") and
      -- get("a", "b") must not collide
      local v = (select(i, ...))
      local t = type(v)
      local s
      if IDENTITY[t] then
        local id = ids[v]
        if not id then
          next_id = next_id + 1
          id = next_id
          ids[v] = id
        end
        s = tostring(id)
      else
        s = tostring(v)
      end
      parts[i] = t:sub(1, 1) .. #s .. ":" .. s
    end
    return table.concat(parts, "\31")
  end
end

---@param make fun(...): any
---@param opts { key: (fun(...): any)|nil, weak: boolean|nil }|nil
---@return Lib.Patterns.Flyweight
function M.new(make, opts)
  opts = opts or {}
  local cache = opts.weak and setmetatable({}, { __mode = "v" }) or {}
  local fast = opts.weak and setmetatable({}, { __mode = "v" }) or {}
  return setmetatable({
    make = make,
    keyfn = opts.key or make_default_key(),
    default_key = opts.key == nil,
    cache = cache,
    fast = fast,
  }, F)
end

---@param ... any
---@return any
function F:get(...)
  if self.default_key and select("#", ...) == 1 then
    -- one primitive argument: the value is its own key (1 and "1" are different Lua keys), no string built
    local a = ...
    local t = type(a)
    if t == "string" or t == "number" or t == "boolean" then
      if a ~= a then
        return self.make(a)
      end
      local v = self.fast[a]
      if v == nil then
        v = self.make(a)
        self.fast[a] = v
      end
      return v
    end
  end
  local key = self.keyfn(...)
  local v = self.cache[key]
  if v == nil then
    v = self.make(...)
    self.cache[key] = v
  end
  return v
end

---Number of cached instances.
---@return integer
function F:size()
  local n = 0
  for _ in pairs(self.cache) do
    n = n + 1
  end
  for _ in pairs(self.fast) do
    n = n + 1
  end
  return n
end

function F:clear()
  for k in pairs(self.cache) do
    self.cache[k] = nil
  end
  for k in pairs(self.fast) do
    self.fast[k] = nil
  end
end

return M
