---@module 'lib.lua.patterns.chain_of_responsibility'
--- Chain of responsibility: an ordered list of handlers; the first one that claims the request ends the
--- chain.
---
--- A handler is `fn(request, ...) -> handled, result`. Returning a falsy `handled` passes the request on.
--- A handler that raises counts as "not handled"; the error is collected, the chain continues.
---
--- ```lua
--- local chain = require("lib.lua.patterns.chain_of_responsibility").new()
--- chain:add("lua", function(path) if path:match("%.lua$") then return true, "lua file" end end)
--- chain:add("any", function(path) return true, "other" end)
--- chain:handle("a.lua") --> true, "lua file", "lua", {}
--- ```

require("lib.lua.patterns.chain_of_responsibility.@types")

local M = {}

---@class Lib.Patterns.Chain
local C = {}
C.__index = C

---@return Lib.Patterns.Chain
function M.new()
  return setmetatable({ handlers = {} }, C)
end

---Append a handler; `opts.first = true` puts it at the front. A handler with the same name is replaced.
---@param name string
---@param fn fun(request: any, ...): boolean|nil, any
---@param opts { first: boolean|nil }|nil
---@return Lib.Patterns.Chain
function C:add(name, fn, opts)
  if type(fn) ~= "function" then
    error("chain_of_responsibility.add: handler must be a function", 2)
  end
  self:remove(name)
  local entry = { name = name, fn = fn }
  if opts and opts.first then
    table.insert(self.handlers, 1, entry)
  else
    self.handlers[#self.handlers + 1] = entry
  end
  return self
end

---@param name string
---@return boolean
function C:remove(name)
  for i, h in ipairs(self.handlers) do
    if h.name == name then
      table.remove(self.handlers, i)
      return true
    end
  end
  return false
end

---@return string[]
function C:names()
  local out = {}
  for i, h in ipairs(self.handlers) do
    out[i] = h.name
  end
  return out
end

---Offer the request to the handlers in order.
---@param request any
---@param ... any
---@return boolean handled
---@return any result
---@return string|nil handler_name
---@return any[] errors
function C:handle(request, ...)
  local errors = {}
  for _, h in ipairs(self.handlers) do
    local ok, handled, result = pcall(h.fn, request, ...)
    if not ok then
      errors[#errors + 1] = handled
    elseif handled then
      return true, result, h.name, errors
    end
  end
  return false, nil, nil, errors
end

return M
