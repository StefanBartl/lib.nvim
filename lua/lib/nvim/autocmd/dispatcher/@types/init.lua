---@module 'lib.nvim.autocmd.dispatcher.@types'
---@deprecated Use `lib.nvim.bindings.autocmd.dispatcher.@types`.
--- Compatibility shim; the rationale is in `lib/nvim/bindings/init.lua` and in
--- this module's former parent. Delete once nothing requires the old path.

vim.deprecate(
  "lib.nvim.autocmd.dispatcher.@types",
  "lib.nvim.bindings.autocmd.dispatcher.@types",
  "a future release",
  "lib.nvim",
  false
)

return require("lib.nvim.bindings.autocmd.dispatcher.@types")
