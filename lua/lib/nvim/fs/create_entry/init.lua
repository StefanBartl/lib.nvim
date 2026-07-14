---@module 'lib.nvim.fs.create_entry'
--- Create a file or directory relative to a parent directory.
---
--- A trailing path separator on `name` selects directory creation
--- (`mkdir -p`); otherwise a new empty file is created (parent directories
--- are created as needed). Pure filesystem side effect only — no `notify`,
--- no buffer opening. Callers (picker actions, commands, …) decide how to
--- report the result and whether to open the created file.

require("lib.nvim.fs.create_entry.@types")

local fn = vim.fn

---True when `path` ends with a `/` or `\` separator.
---@param path string
---@return boolean
local function ends_with_separator(path)
  return path:match("[/\\]$") ~= nil
end

---@param parent_dir string Parent directory the entry is created in
---@param name string Entry name; a trailing separator creates a directory
---@return boolean ok
---@return "file"|"directory"|nil kind
---@return string|nil path_or_err Absolute path on success, error message otherwise
return function(parent_dir, name)
  if type(parent_dir) ~= "string" or parent_dir == "" then
    return false, nil, "invalid parent_dir"
  end
  if type(name) ~= "string" or name == "" then
    return false, nil, "invalid name"
  end

  local full_path = fn.resolve(parent_dir .. "/" .. name)

  if ends_with_separator(name) then
    local dir_path = full_path:gsub("[/\\]$", "")
    local ok, err = pcall(fn.mkdir, dir_path, "p")
    if not ok then
      return false, nil, "mkdir failed: " .. tostring(err)
    end
    return true, "directory", dir_path
  end

  if fn.filereadable(full_path) == 1 then
    return false, nil, "file already exists: " .. full_path
  end

  local parent = fn.fnamemodify(full_path, ":h")
  if fn.isdirectory(parent) == 0 then
    local ok, err = pcall(fn.mkdir, parent, "p")
    if not ok then
      return false, nil, "mkdir failed: " .. tostring(err)
    end
  end

  local file, err = io.open(full_path, "w")
  if not file then
    return false, nil, "open failed: " .. (err or full_path)
  end
  file:close()

  return true, "file", full_path
end
