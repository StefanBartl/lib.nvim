---@module 'lib.nvim.patterns'
--- Namespace aggregator for the design-pattern modules that need the editor (timers, scheduling); see
--- docs/patterns.md. Editor-independent patterns live in `lib.lua.patterns`. Indexing loads lazily:
---
---   local patterns = require("lib.nvim.patterns")
---   patterns.throttle   -- == require("lib.nvim.patterns.throttle")

local cache = {}

return setmetatable({}, {
  __index = function(_, key)
    if cache[key] == nil then
      cache[key] = require("lib.nvim.patterns." .. key)
    end
    return cache[key]
  end,
})
