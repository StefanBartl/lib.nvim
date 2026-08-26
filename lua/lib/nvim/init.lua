---@module 'lib.nvim'
--- Namespace aggregator for the Neovim-specific helpers.
---
--- These modules are adapters over the `vim` API. Indexing loads the submodule
--- lazily:
---
---   local Nvim = require("lib.nvim")
---   Nvim.notify   -- == require("lib.nvim.notify")
---   Nvim.map      -- == require("lib.nvim.bindings.keymap")
---   Nvim.core     -- == require("lib.nvim.core")  (has_exec, simple_echo, …)
---
--- Requiring a submodule directly still works, and is friendlier to
--- tree-shaking:
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
