---@module 'lib.nvim.usercmd.composer.argtypes'
---@deprecated Use `lib.nvim.bindings.usercmd.composer.argtypes`.
--- Compatibility shim; the rationale is in `lib/nvim/bindings/init.lua` and in
--- this module's former parent. Delete once nothing requires the old path.

vim.deprecate(
  "lib.nvim.usercmd.composer.argtypes",
  "lib.nvim.bindings.usercmd.composer.argtypes",
  "a future release",
  "lib.nvim",
  false
)

return require("lib.nvim.bindings.usercmd.composer.argtypes")
