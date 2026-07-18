---@module 'lib.nvim.fs.find_upward_dir'
--- Walk upward from `from` and return the nearest ancestor directory holding
--- one of `names`.
---
--- Markers may be plain basenames (`.git`, `package.json`) or shell-style
--- globs (`*.rockspec`). `vim.fs.find`'s name-list form compares names
--- verbatim and cannot express a glob, so a marker set containing one is
--- translated into `vim.fs.find`'s predicate form instead. Plain marker sets
--- keep taking the (cheaper) list path — behaviour there is unchanged.

local matcher = require("lib.nvim.fs.find_upward_dir.matcher")

---@param names string[] Marker basenames; `*` and `?` globs are supported
---@param from string Directory to start the upward walk at
---@return string|nil
return function(names, from)
  local query = matcher.has_glob(names) and matcher.build(names) or names
  local found = vim.fs.find(query, { path = from, upward = true })
  if found and found[1] then
    return vim.fs.dirname(found[1])
  end
  return nil
end
