---@module 'lib.nvim.bindings'
--- Namespace aggregator for the three ways this library binds behaviour to
--- Neovim: keymaps, user commands, and autocommands.
---
--- They were three unrelated top-level modules until they were collected here.
--- The grouping is not filing for its own sake -- the three answer the same
--- question ("how does a plugin expose an action?") and a plugin almost always
--- registers all three from the same place, so they share conventions: the same
--- `desc` handling, the same defensive callback wrapping, the same
--- "declared once, overridable by the user" shape.
---
---   local bindings = require("lib.nvim.bindings")
---   bindings.keymap    -- == require("lib.nvim.bindings.keymap")
---   bindings.usercmd   -- == require("lib.nvim.bindings.usercmd")
---   bindings.autocmd   -- == require("lib.nvim.bindings.autocmd")
---
--- Indexing loads lazily, mirroring `lib.nvim` itself. Requiring a submodule
--- directly still works and stays friendlier to tree-shaking.
---
--- The former paths (`lib.nvim.map`, `lib.nvim.usercmd`, `lib.nvim.autocmd`)
--- are **gone** (2026-08-27). They resolved through deprecation shims while
--- the plugins were migrated one repo at a time; every repo is on the new
--- paths now, and lib.nvim is pre-1.0 with a breaking-changes notice in the
--- first line of its README, so carrying them further buys nothing.

local cache = {}

return setmetatable({}, {
  __index = function(_, key)
    if cache[key] == nil then
      cache[key] = require("lib.nvim.bindings." .. key)
    end
    return cache[key]
  end,
})
