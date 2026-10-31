---@module 'lib.lua.patterns'
--- Namespace aggregator for the editor-independent design-pattern modules (see docs/patterns.md).
--- Indexing loads the submodule lazily:
---
---   local patterns = require("lib.lua.patterns")
---   patterns.result   -- == require("lib.lua.patterns.result")

local cache = {}

return setmetatable({}, {
  __index = function(_, key)
    if cache[key] == nil then
      cache[key] = require("lib.lua.patterns." .. key)
    end
    return cache[key]
  end,
})
