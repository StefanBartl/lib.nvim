---@module 'lib.nvim.cross.fs.separators.normalize'
--- Normalizes path separators for the current OS.
--- Returns a string with OS-appropriate separators or nil on invalid input.

---@param path string
---@return string|nil
return function (path)
  -- ensure the parameter is a string and fail early otherwise.
  assert(
    type(path) == "string",
    "[lib.nvim.normalize.os_sep] parameter 'path' must be type of string, but is " .. type(path)
  )

  -- use vim.loop.os_uname() to detect Windows.
  -- Some systems expose "Windows" in version; using sysname may be more direct on some platforms.
  local is_windows = false
  local ok, osu = pcall(vim.loop.os_uname)
  if ok and type(osu) == "table" and osu.version then
    is_windows = osu.version:match("Windows") and true or false
  elseif ok and type(osu) == "table" and osu.sysname then
    -- fallback if version isn't present
    is_windows = osu.sysname:match("Windows") and true or false
  end

  local r
  if is_windows then
    -- Replace forward slashes "/" with a single backslash "\".
    -- In the Lua source literal, "\\" represents one backslash character.
    r = path:gsub("/", "\\")
    return r
  else

    -- Replace backslashes "\" with forward slashes "/".
    -- Matching a literal backslash in Lua patterns requires escaping the backslash for the pattern.
    -- The pattern string for a single backslash must be written as "\\\\" in source code:
    --  - "\\" (Lua literal) -> single backslash in resulting string
    --  - Pattern to match backslash needs two backslashes ("\\") -> source literal "\\\\"
    r = path:gsub("\\\\", "/")
    return r
  end
end
