---@module 'lib.nvim.fs.relpath'
--- Compute `path` relative to `base`.
---
--- Both arguments are made absolute and normalized to forward slashes, so this
--- works with mixed separators on Windows. `base` is treated as a directory:
--- when `path` lives under it, the base prefix (and the separating slash) is
--- stripped; when it does not, the absolute `path` is returned unchanged. A
--- `path` equal to `base` yields ".".
---
---@param path string
---@param base string
---@return string
return function(path, base)
  base = vim.fn.fnamemodify(base, ":p"):gsub("\\", "/"):gsub("/+$", "")
  path = vim.fn.fnamemodify(path, ":p"):gsub("\\", "/"):gsub("/+$", "")
  if path == base then
    return "."
  end
  if path:sub(1, #base + 1) == base .. "/" then
    return path:sub(#base + 2)
  end
  return path
end
