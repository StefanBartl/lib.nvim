---@module 'lib.lua.patterns.event_bus'
--- Event bus: publish/subscribe on named topics, without the editor.
---
--- A listener that raises does not stop the others: errors are collected and returned by `emit`.
--- `on()` returns the unsubscribe function. The topic `"*"` receives every event as `(topic, ...)`.
---
--- ```lua
--- local bus = require("lib.lua.patterns.event_bus").new()
--- local off = bus:on("saved", function(path) print(path) end)
--- bus:emit("saved", "a.lua") --> 1, {}   (listeners called, errors)
--- off()
--- ```
---
--- For editor-aware needs (priorities, vetoable events) use `lib.nvim.hooks`.

require("lib.lua.patterns.event_bus.@types")

local M = {}

---@class Lib.Patterns.EventBus
local B = {}
B.__index = B

---@return Lib.Patterns.EventBus
function M.new()
  return setmetatable({ topics = {} }, B)
end

---@param topic string
---@param fn function
---@return fun() unsubscribe
function B:on(topic, fn)
  local list = self.topics[topic]
  if not list then
    list = {}
    self.topics[topic] = list
  end
  local entry = { fn = fn }
  list[#list + 1] = entry
  return function()
    for i, e in ipairs(list) do
      if e == entry then
        table.remove(list, i)
        return
      end
    end
  end
end

---Subscribe for one event only.
---@param topic string
---@param fn function
---@return fun() unsubscribe
function B:once(topic, fn)
  local off
  off = self:on(topic, function(...)
    off()
    return fn(...)
  end)
  return off
end

---Call every listener of `topic` (then of `"*"`) in subscription order.
---@param topic string
---@param ... any
---@return integer called
---@return any[] errors
function B:emit(topic, ...)
  local called, errors = 0, {}
  local function run(list, with_topic, ...)
    if not list then
      return
    end
    local snapshot = {}
    for i, e in ipairs(list) do
      snapshot[i] = e
    end
    for _, e in ipairs(snapshot) do
      called = called + 1
      local ok, err
      if with_topic then
        ok, err = pcall(e.fn, topic, ...)
      else
        ok, err = pcall(e.fn, ...)
      end
      if not ok then
        errors[#errors + 1] = err
      end
    end
  end
  run(self.topics[topic], false, ...)
  if topic ~= "*" then
    run(self.topics["*"], true, ...)
  end
  return called, errors
end

---Number of listeners on `topic`.
---@param topic string
---@return integer
function B:count(topic)
  local list = self.topics[topic]
  return list and #list or 0
end

---Drop the listeners of one topic, or of all topics.
---@param topic string|nil
function B:clear(topic)
  if topic then
    self.topics[topic] = nil
  else
    self.topics = {}
  end
end

return M
