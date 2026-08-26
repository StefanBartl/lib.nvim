---@module 'lib.nvim.autocmd.dispatcher.filetype'
---@deprecated Use `lib.nvim.bindings.autocmd.dispatcher.filetype`.
--- Compatibility shim; the rationale is in `lib/nvim/bindings/init.lua` and in
--- this module's former parent. Delete once nothing requires the old path.

vim.deprecate(
  "lib.nvim.autocmd.dispatcher.filetype",
  "lib.nvim.bindings.autocmd.dispatcher.filetype",
  "a future release",
  "lib.nvim",
  false
)

return require("lib.nvim.bindings.autocmd.dispatcher.filetype")
