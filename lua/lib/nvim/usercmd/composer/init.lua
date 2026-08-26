---@module 'lib.nvim.usercmd.composer'
---@deprecated Use `lib.nvim.bindings.usercmd.composer`.
--- Compatibility shim; the rationale is in `lib/nvim/bindings/init.lua` and in
--- this module's former parent. Delete once nothing requires the old path.

vim.deprecate(
  "lib.nvim.usercmd.composer",
  "lib.nvim.bindings.usercmd.composer",
  "a future release",
  "lib.nvim",
  false
)

---@type Lib.UserCmd.Composer
return require("lib.nvim.bindings.usercmd.composer")
