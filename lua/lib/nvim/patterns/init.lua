---@module 'lib.nvim.patterns'
--- Namespace aggregator for the design-pattern modules that need the editor (timers, scheduling); see
--- docs/patterns.md. Editor-independent patterns live in `lib.lua.patterns`. Indexing loads lazily:
---
---   local patterns = require("lib.nvim.patterns")
---   patterns.throttle   -- == require("lib.nvim.patterns.throttle")

local cache = {}

return setmetatable({}, {
  __index = function(_, key)
    -- only plain module names: no dots or slashes, so a key can never reach outside the pattern modules
    if type(key) ~= "string" or not key:match("^[%a_][%w_]*$") then
      return nil
    end
    if cache[key] == nil then
      local name = "lib.nvim.patterns." .. key
      local ok, mod = pcall(require, name)
      if not ok then
        -- an unknown name is nil; a real error inside an existing module is not hidden
        if tostring(mod):find("module '" .. name .. "' not found", 1, true) then
          return nil
        end
        error(mod, 0)
      end
      cache[key] = mod
    end
    return cache[key]
  end,
})
