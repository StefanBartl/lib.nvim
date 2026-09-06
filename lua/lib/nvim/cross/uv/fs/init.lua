---@module 'lib.nvim.cross.uv.fs'
--- Resolve the current working directory via libuv, compatible across Neovim
--- versions. Same body as `lib.nvim.cross.fs._cwd`; kept separate because it is
--- not wired into the `cross` aggregate table (require it directly).

---@return string
return function()
  -- Prefer vim.uv on newer Neovim; fall back to vim.loop for older builds.
  local uv = vim.uv or vim.loop
  return uv and uv.cwd() or vim.fn.getcwd()
end
