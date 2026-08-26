---@module 'lib.nvim.autocmd.augroup'
---@deprecated Use `lib.nvim.bindings.autocmd.augroup`.
--- Compatibility shim; the rationale is in `lib/nvim/bindings/init.lua` and in
--- this module's former parent. Delete once nothing requires the old path.

vim.deprecate(
  "lib.nvim.autocmd.augroup",
  "lib.nvim.bindings.autocmd.augroup",
  "a future release",
  "lib.nvim",
  false
)

return require("lib.nvim.bindings.autocmd.augroup")
