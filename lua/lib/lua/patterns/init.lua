---@module 'lib.lua.patterns'
--- Namespace aggregator for the editor-independent design-pattern modules (see docs/patterns.md).
--- Indexing loads the submodule lazily:
---
---   local patterns = require("lib.lua.patterns")
---   patterns.result   -- == require("lib.lua.patterns.result")

local cache = {}

return setmetatable({}, {
  __index = function(_, key)
    -- only plain module names: no dots or slashes, so a key can never reach outside the pattern modules
    if type(key) ~= "string" or not key:match("^[%a_][%w_]*$") then
      return nil
    end
    if cache[key] == nil then
      local name = "lib.lua.patterns." .. key
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
