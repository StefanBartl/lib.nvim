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

---@type Lib.Cache
local M = {}

M.disk = require("lib.nvim.cache.disk")
M.memory = require("lib.nvim.cache.memory")

---@type Lib.Cache
return M
