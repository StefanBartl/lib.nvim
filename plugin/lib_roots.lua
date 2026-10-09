-- Startup hook of `lib.nvim.fs.roots`: make `$NVIM_CONFIG_DIR` a real environment variable
-- (`stdpath("config")`) unless one is set, so child processes and `vim.fn.expand` understand it
-- too. Never overwrites. Opt out with `vim.g.lib_nvim_roots_no_export = true` before this runs.
if vim.g.loaded_lib_nvim_roots == 1 then
  return
end
vim.g.loaded_lib_nvim_roots = 1

require("lib.nvim.fs.roots")
