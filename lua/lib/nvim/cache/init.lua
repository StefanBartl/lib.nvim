---@module 'lib.nvim.cache'
--- Caching namespace: a persistent JSON disk cache and a generic in-memory
--- TTL/changedtick namespace cache for event handlers.
---
---   local cache = require("lib.nvim.cache")
---   cache.disk.save("github_issues", data)
---   local ns = cache.memory.namespace("my_plugin.something", { ttl = 5 })
---
--- Direct requiring stays tree-shake friendly:
---   local disk = require("lib.nvim.cache.disk")
---   local memory = require("lib.nvim.cache.memory")

require("lib.nvim.cache.@types")

local M = {}

M.disk = require("lib.nvim.cache.disk")
M.memory = require("lib.nvim.cache.memory")

---The `:Lib cache stats` route, for `lib.nvim_usrcmds` to merge into the `:Lib` verb it builds (data,
---not registered here, so exactly one place owns the verb). It shows the hit rate, size and evictions
---of every in-memory namespace -- of every plugin that uses `lib.nvim.cache.memory` -- in one table.
---@return table[] routes
function M.routes()
  return {
    {
      path = { "cache", "stats" },
      args = {},
      desc = "Hit rate, entries and evictions of every in-memory cache namespace",
      run = function()
        vim.api.nvim_echo({ { table.concat(M.memory.format_stats(), "\n") } }, true, {})
      end,
    },
  }
end

---@type Lib.Cache
return M
