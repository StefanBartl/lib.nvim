---@module 'lib.nvim.map'
---@deprecated Use `lib.nvim.bindings.keymap`.
--- Compatibility shim. The module moved to `lib.nvim.bindings.keymap` when
--- keymaps, user commands and autocommands were collected under
--- `lib.nvim.bindings` -- see that module's header for why.
---
--- This file exists so the move is not a flag day: lib.nvim is a dependency of
--- every plugin here, and without a shim, updating lib.nvim would break every
--- one of them until each had been updated too -- in whichever order a user's
--- plugin manager happens to fetch them. With it, both paths work and the
--- call sites can be migrated repo by repo.
---
--- Delete once no repository requires the old path any more.

vim.deprecate("lib.nvim.map", "lib.nvim.bindings.keymap", "a future release", "lib.nvim", false)

---@type Lib.Map
return require("lib.nvim.bindings.keymap")
