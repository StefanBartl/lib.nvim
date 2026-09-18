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
--- were meant to be gone by 2026-08-27 once every consuming repo moved to the
--- paths here, but the migration silently stalled: all three lived on as
--- full, independent module trees (not shims), diverged from their
--- `bindings` counterparts (the composer here gained per-verb notify
--- prefixes and declaration-site tracking the old one never got), and
--- lib.nvim's own `lib.nvim.telemetry` kept requiring the old `autocmd` and
--- `usercmd` directly. One consequence: the augroup cached-clear regression
--- fixed in this module's `group()`/`get_augroup()` had to be re-found and
--- re-fixed in the old copy too (see `TESTS/autocmd_spec.lua`) — a fix
--- landing only in the path everyone *assumed* was the only one left behind
--- did not reach callers still on the other one. That migration is now
--- actually finished: `lib.nvim.map`, `lib.nvim.usercmd` and `lib.nvim.autocmd`
--- are gone (2026-09-18), `lib.nvim.telemetry` requires the paths here, and
--- the one external fleet dependent (ai.nvim, on `usercmd.composer`) was
--- updated first. If a stray `require("lib.nvim.usercmd")` (etc.) surfaces
--- again, it is a genuine bug, not a documentation lag — file it as one.

local cache = {}

return setmetatable({}, {
  __index = function(_, key)
    if cache[key] == nil then
      cache[key] = require("lib.nvim.bindings." .. key)
    end
    return cache[key]
  end,
})
