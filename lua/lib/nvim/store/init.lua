---@module 'lib.nvim.store'
--- Persistent-storage namespace.
---
---   local store = require("lib.nvim.store")
---   store.project.save("cascade/anchors", { version = 1 })
---
--- Direct requiring stays tree-shake friendly:
---   local project = require("lib.nvim.store.project")

require("lib.nvim.store.@types")

---@type Lib.Store
local M = {}

M.project = require("lib.nvim.store.project")

---@type Lib.Store
return M
