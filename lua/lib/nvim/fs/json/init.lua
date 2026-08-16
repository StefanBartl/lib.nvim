---@module 'lib.nvim.fs.json'
--- Read/write JSON files, built on `lib.nvim.json` (encode/decode) plus
--- `lib.nvim.fs.read` and `lib.nvim.fs.write.to_file`.
---
--- Writes are atomic: the encoded content is written to `path .. ".tmp"`
--- first, then renamed over `path` — atomic on POSIX, best-effort on
--- Windows (see `M.write` for details).
---
---```lua
--- local json = require("lib.nvim.fs.json")
---
--- local ok, err = json.write("/tmp/state.json", { count = 1 })
--- local tbl, err2 = json.read("/tmp/state.json")
---```

require("lib.nvim.fs.json.@types")

local read = require("lib.nvim.fs.read")
local write_to_file = require("lib.nvim.fs.write.to_file")
local nvim_json = require("lib.nvim.json")

local uv = vim.uv or vim.loop

local M = {}

---Read and JSON-decode the file at `path`.
---@param path string
---@return table|nil decoded
---@return string|nil err
function M.read(path)
  local content, read_err = read(path)
  if not content then
    return nil, "read failed: " .. tostring(read_err)
  end

  return nvim_json.decode(content)
end

---JSON-encode `tbl` and write it to `path` atomically: write to a sibling
---`.tmp` file first, then rename it over `path`. Renaming is atomic on
---POSIX filesystems; on Windows `fs_rename` is best-effort (it can fail if
---`path` is open elsewhere) but still avoids leaving a half-written file.
---@param path string
---@param tbl table
---@return boolean ok
---@return string|nil err
function M.write(path, tbl)
  local encoded, encode_err = nvim_json.encode(tbl)
  if not encoded then
    return false, "encode failed: " .. tostring(encode_err)
  end

  local tmp_path = path .. ".tmp"
  local ok_write, write_err = write_to_file(tmp_path, encoded)
  if not ok_write then
    return false, "write failed: " .. tostring(write_err)
  end

  local ok_rename, rename_err = uv.fs_rename(tmp_path, path)
  if not ok_rename then
    pcall(os.remove, tmp_path)
    return false, "rename failed: " .. tostring(rename_err)
  end

  return true, nil
end

---@type Lib.Fs.Json
return M
