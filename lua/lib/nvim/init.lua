---@module 'lib.nvim'
--- Namespace aggregator for the Neovim-specific helpers.
---
--- These modules are adapters over the `vim` API. Indexing loads the submodule
--- lazily:
---
---   local Nvim = require("lib.nvim")
---   Nvim.notify   -- == require("lib.nvim.notify")
---   Nvim.core     -- == require("lib.nvim.core")  (has_exec, simple_echo, …)
---
--- Note: this aggregator mirrors directory structure 1:1 (`Nvim.x` ==
--- `require("lib.nvim.x")`), so it has no flattened shortcuts. `Nvim.map` does
--- NOT resolve -- for the `map`/`usercmd`/`autocmd` short names, go through
--- the flattened top-level aggregator instead: `require("lib").map`.
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
