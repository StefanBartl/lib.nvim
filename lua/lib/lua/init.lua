---@module 'lib.lua'
--- Namespace-Aggregator für die editorunabhängigen Lua-Helfer.
---
--- Diese Module benötigen KEINE `vim`-API und sind damit auch außerhalb von
--- Neovim verwendbar/testbar. Zugriff lädt das jeweilige Submodul lazy:
---
---   local Lua = require("lib.lua")
---   Lua.tables    -- == require("lib.lua.tables")
---   Lua.strings   -- == require("lib.lua.strings")
---
--- Direktes Requiren bleibt natürlich möglich und ist baumschüttelfreundlicher:
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
