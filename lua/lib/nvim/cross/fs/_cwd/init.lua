---@module 'lib.nvim.cross.fs._cwd'

-- Resolve the current working directory via libuv, compatible across NVIM versions.
---@return string
return function()
  -- Prefer vim.uv on newer Neovim; fall back to vim.loop for older builds.
  local uv = vim.uv or vim.loop
  return uv and uv.cwd() or vim.fn.getcwd()
end
