---@module 'lib.nvim.cross.fs.expand_path'
--- Expand `~`, `$VAR`/`${VAR}` (POSIX) and `%VAR%` (Windows) references in a raw
--- path string. Pure string expansion — does not normalize separators or resolve
--- `.`/`..` (see `lib.nvim.cross.fs.separators` / `lib.nvim.fs.path` for that).
---
--- A LEADING `$NAME` / `${NAME}` / `%NAME%` that names a root of `lib.nvim.fs.roots` is resolved by
--- the registry first -- so `$NVIM_CONFIG_DIR` works without a real environment variable, and an
--- `extra` root or an injected test source wins over the environment. The root comes back in the
--- registry's spelling (absolute, forward slashes, no trailing slash); the rest of the string goes
--- through the generic expansion below as before. Everything the registry does not know is
--- expanded exactly as it always was.

local roots = require("lib.nvim.fs.roots")

---@param path string
---@return string
return function(path)
  if type(path) ~= "string" or path == "" then
    return path
  end

  local prefix = ""
  local expanded = path

  local matched, root, rest = roots.match(path)
  if matched then
    prefix, expanded = root, rest
  end

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

  return prefix .. expanded
end
