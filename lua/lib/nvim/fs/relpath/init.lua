---@module 'lib.nvim.fs.relpath'
--- Compute path relative to base

return function (path, base)
  base = vim.fn.fnamemodify(base, ":p") -- ensure absolute
  path = vim.fn.fnamemodify(path, ":p")
  if path:sub(1, #base) == base then
    path = path:sub(#base + 2) -- +2: skip slash
  end
  return path
end

