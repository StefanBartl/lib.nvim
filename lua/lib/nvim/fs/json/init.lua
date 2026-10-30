---@module 'lib.nvim.fs.json'
--- Read/write JSON files, built on `lib.nvim.json` (encode/decode) plus
--- `lib.nvim.fs.read` and `lib.nvim.fs.write.to_file`.
---
--- Writes are atomic: the encoded content is written to a sibling temp file
--- unique per write (`<stem>.<pid>-<n>-<hrtime><ext>.tmp`, see `M.tmp_path`)
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

-- Per-process counter: two writes in the same nanosecond still get different names.
local seq = 0

---The temp file `M.write` stages `path` in: same directory (so the rename stays atomic), unique per process and
---call (so two writers never share one), and ending in `<ext>.tmp` like the old fixed `<path>.tmp` did, so a
---sweeper matching `*.json.tmp` still finds a write a crash left behind.
---`/d/state.json` -> `/d/state.<pid>-<n>-<hrtime>.json.tmp`; `/d/state` -> `/d/state.<pid>-<n>-<hrtime>.tmp`.
---@param path string
---@return string
function M.tmp_path(path)
  seq = seq + 1
  local unique = ("%d-%d-%d"):format(uv.os_getpid(), seq, uv.hrtime())
  -- The extension of the file name only: a dot in a directory name or a leading-dot name has none.
  local stem, ext = path:match("^(.*[^/\\])(%.[^./\\]+)$")
  if not stem then
    return ("%s.%s.tmp"):format(path, unique)
  end
  return ("%s.%s%s.tmp"):format(stem, unique, ext)
end

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
---temp file unique to this call (`M.tmp_path`) first, then rename it over `path`. Renaming is atomic on
---POSIX filesystems; on Windows `fs_rename` is best-effort (it can fail if
---`path` is open elsewhere) but still avoids leaving a half-written file.
---A symlink `path` is written through (the link stays a link); a dangling link is replaced.
---@param path string
---@param tbl table
---@return boolean ok
---@return string|nil err
function M.write(path, tbl)
  local encoded, encode_err = nvim_json.encode(tbl)
  if not encoded then
    return false, "encode failed: " .. tostring(encode_err)
  end

  -- A symlink as target (a dotfile manager) stays a link: the rename replaces what it points to.
  local lst = uv.fs_lstat(path)
  if lst and lst.type == "link" then
    path = uv.fs_realpath(path) or path
  end

  local tmp_path = M.tmp_path(path)
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
