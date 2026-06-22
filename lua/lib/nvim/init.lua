---@module 'lib.nvim'
--- Namespace-Aggregator für die Neovim-spezifischen Helfer.
---
--- Diese Module sind Adapter auf die `vim`-API. Zugriff lädt das jeweilige
--- Submodul lazy:
---
---   local Nvim = require("lib.nvim")
---   Nvim.notify   -- == require("lib.nvim.notify")
---   Nvim.map      -- == require("lib.nvim.map")
---   Nvim.core     -- == require("lib.nvim.core")  (has_exec, simple_echo, …)
---
--- Direktes Requiren bleibt möglich und ist baumschüttelfreundlicher:
---   local notify = require("lib.nvim.notify")

local cache = {}

return setmetatable({}, {
  __index = function(_, key)
    if cache[key] == nil then
      cache[key] = require("lib.nvim." .. key)
    end
    return cache[key]
  end,
})
