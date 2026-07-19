---@module 'lib.nvim.fs.create_entry'
--- Create a file or directory relative to a parent directory.
---
--- A trailing path separator on `name` selects directory creation
--- (`mkdir -p`); otherwise a new empty file is created (parent directories
--- are created as needed). Pure filesystem side effect only — no `notify`,
--- no buffer opening. Callers (picker actions, commands, …) decide how to
--- report the result and whether to open the created file.

require("lib.nvim.fs.create_entry.@types")

local mkdirp = require("lib.nvim.fs.mkdirp")
local is_valid_filename = require("lib.nvim.fs.is_valid_filename")

local fn = vim.fn

---True when `path` ends with a `/` or `\` separator.
---@param path string
---@return boolean
local function ends_with_separator(path)
  return path:match("[/\\]$") ~= nil
end

---Validate every path segment of `name` individually (not the whole string
---at once — `name` may legitimately contain `/`/`\` to create a new file
---inside a not-yet-existing subdirectory in one step).
---@param name string
---@return boolean ok
---@return string|nil err
local function validate_segments(name)
  for segment in name:gmatch("[^/\\]+") do
    local ok, err = is_valid_filename(segment)
    if not ok then
      return false, err .. ": " .. segment
    end
  end
  return true, nil
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
  local segments_ok, segments_err = validate_segments(name)
  if not segments_ok then
    return false, nil, segments_err
  end

  local full_path = fn.resolve(parent_dir .. "/" .. name)

  if ends_with_separator(name) then
    local dir_path = full_path:gsub("[/\\]$", "")
    local ok, err = mkdirp(dir_path)
    if not ok then
      return false, nil, "mkdir failed: " .. tostring(err)
    end
    return true, "directory", dir_path
  end

  if fn.filereadable(full_path) == 1 then
    return false, nil, "file already exists: " .. full_path
  end

  local parent = fn.fnamemodify(full_path, ":h")
  local ok, err = mkdirp(parent)
  if not ok then
    return false, nil, "mkdir failed: " .. tostring(err)
  end

  local file, err = io.open(full_path, "w")
  if not file then
    return false, nil, "open failed: " .. (err or full_path)
  end
  file:close()

  return true, "file", full_path
end
