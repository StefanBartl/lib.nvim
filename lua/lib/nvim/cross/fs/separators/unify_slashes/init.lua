---@module 'lib.nvim.cross.fs.separators.unify_slashes'
--- Convert every backslash in `path` to a forward slash — a pure string
--- transform: no expansion, no absolute-path resolution, no collapsing of
--- repeated separators. Use this to keep a path in forward-slash form
--- regardless of the current OS (Neovim's own API and libuv both accept "/"
--- on Windows too) — the opposite direction from M.separators.normalize,
--- which converts *to* the current OS's native separator.

---@param path string
---@return string
return function (path)
  assert(
    type(path) == "string",
    "[lib.nvim.cross.fs.separators.unify_slashes] parameter 'path' must be type of string, but is " .. type(path)
  )
  return (path:gsub("\\", "/"))
end
