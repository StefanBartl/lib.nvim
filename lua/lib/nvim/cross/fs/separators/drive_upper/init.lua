---@module 'lib.nvim.cross.fs.separators.drive_upper'
--- Uppercase a Windows drive-letter prefix ("c:/foo" -> "C:/foo"). No-op on
--- paths without a bare drive prefix (POSIX paths, UNC shares, relative
--- paths). Pure string transform: no expansion, no disk access.

---@param path string
---@return string
return function(path)
  assert(
    type(path) == "string",
    "[lib.nvim.cross.fs.separators.drive_upper] parameter 'path' must be type of string, but is " .. type(path)
  )
  return (path:gsub("^(%a):", function(d)
    return d:upper() .. ":"
  end))
end
