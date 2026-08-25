---@module 'lib.lua'
--- Namespace aggregator for the editor-independent Lua helpers.
---
--- None of these modules touch the `vim` API, so they are usable and testable
--- outside Neovim too. Indexing loads the submodule lazily:
---
---   local Lua = require("lib.lua")
---   Lua.tables    -- == require("lib.lua.tables")
---   Lua.strings   -- == require("lib.lua.strings")
---
--- Requiring a submodule directly still works, and is friendlier to
--- tree-shaking:
---   local tables = require("lib.lua.tables")

local cache = {}

return setmetatable({}, {
  __index = function(_, key)
    if cache[key] == nil then
      cache[key] = require("lib.lua." .. key)
    end
    return cache[key]
  end,
})
