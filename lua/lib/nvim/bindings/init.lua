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
--- were meant to be **gone** (2026-08-27) once every consuming repo moved to
--- the paths here. That migration is not actually finished: all three still
--- exist as full, independent modules (not shims) under `lua/lib/nvim/`, and
--- lib.nvim's own `lib.nvim.telemetry` still requires `lib.nvim.autocmd` and
--- `lib.nvim.usercmd` directly rather than through `bindings`. Two of this
--- module's own fixes (the augroup cached-clear regression, see
--- `TESTS/nvim_autocmd_spec.lua`) had to be applied twice, once per copy,
--- for exactly this reason — a fix landing in only the path everyone
--- *assumed* was the only one left behind silently does not reach callers
--- still on the other one. Until the old paths are actually deleted (or
--- turned into real shims), treat them as live, dependent-on API, not dead
--- code.

local cache = {}

return setmetatable({}, {
  __index = function(_, key)
    if cache[key] == nil then
      cache[key] = require("lib.nvim.bindings." .. key)
    end
    return cache[key]
  end,
})
