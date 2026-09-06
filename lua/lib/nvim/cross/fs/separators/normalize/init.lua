---@module 'lib.nvim.cross.fs.separators.normalize'
--- Normalizes path separators for the current OS.
--- Returns a string with OS-appropriate separators or nil on invalid input.

---@param path string
---@return string|nil
return function(path)
  assert(
    type(path) == "string",
    "[lib.nvim.cross.fs.separators.normalize] parameter 'path' must be type of string, but is "
      .. type(path)
  )

  --- CDX: reimplements Windows detection (and checks os_uname().version, not
  --- the usual sysname == "Windows_NT") instead of reusing cross.platform.is_windows.
  local is_windows = false
  local ok, osu = pcall(vim.uv.os_uname)
  if ok and type(osu) == "table" and osu.version then
    is_windows = osu.version:match("Windows") and true or false
  elseif ok and type(osu) == "table" and osu.sysname then
    is_windows = osu.sysname:match("Windows") and true or false
  end

  local r
  if is_windows then
    r = path:gsub("/", "\\")
    return r
  else
    r = path:gsub("\\", "/")
    return r
  end
end
