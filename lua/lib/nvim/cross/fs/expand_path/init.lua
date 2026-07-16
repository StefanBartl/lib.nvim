---@module 'lib.nvim.cross.fs.expand_path'
--- Expand `~`, `$VAR` (POSIX) and `%VAR%` (Windows) references in a raw path
--- string. Pure string expansion — does not normalize separators or resolve
--- `.`/`..` (see `lib.nvim.cross.fs.separators` / `lib.nvim.fs.path` for that).

---@param path string
---@return string
return function(path)
  if type(path) ~= "string" or path == "" then
    return path
  end

  local expanded = path

  if expanded:sub(1, 1) == "~" then
    local home = vim.uv and vim.uv.os_homedir() or vim.loop.os_homedir()
    if home then
      expanded = home .. expanded:sub(2)
    end
  end

  expanded = expanded:gsub("%%([%w_]+)%%", function(name)
    return vim.env[name] or ("%" .. name .. "%")
  end)

  expanded = expanded:gsub("%$([%w_]+)", function(name)
    return vim.env[name] or ("$" .. name)
  end)
  expanded = expanded:gsub("%${([%w_]+)}", function(name)
    return vim.env[name] or ("${" .. name .. "}")
  end)

  return expanded
end
