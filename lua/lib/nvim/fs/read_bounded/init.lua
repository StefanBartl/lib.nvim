---@module 'lib.nvim.fs.read_bounded'
--- Read a file only when it is a regular file of at most `max_bytes` bytes.
---
--- For files that sit in a repository somebody else controls (a `.git/config`
--- in a cloned plugin, a manifest): a FIFO would block the read forever, a
--- device file never ends, a multi-gigabyte file exhausts memory. The type and
--- size are judged on the stat before the file is opened, and again on the open
--- descriptor; the read itself never takes more than `max_bytes + 1` bytes, so a
--- file that grows (or is swapped) in between cannot exhaust memory either.
---
---```lua
--- local read_bounded = require("lib.nvim.fs.read_bounded")
--- local content, err = read_bounded(dir .. "/.git/config", 256 * 1024)
--- -- a symlink is refused instead of followed:
--- local c2 = read_bounded(path, 4096, { follow_symlinks = false })
---```

local uv = vim.uv or vim.loop

---@class Lib.Fs.ReadBoundedOpts
---@field follow_symlinks? boolean  default `true`; `false` refuses a symlink (lstat)

---@param path string
---@param max_bytes integer
---@param opts? Lib.Fs.ReadBoundedOpts
---@return string|nil content
---@return string|nil err
return function(path, max_bytes, opts)
  if type(path) ~= "string" or type(max_bytes) ~= "number" or max_bytes < 0 then
    return nil, "invalid arguments"
  end
  local follow = not (opts and opts.follow_symlinks == false)
  local stat = follow and uv.fs_stat(path) or uv.fs_lstat(path)
  if not stat then
    return nil, "not found: " .. path
  end
  if stat.type ~= "file" then
    return nil, "not a regular file: " .. path
  end
  if stat.size > max_bytes then
    return nil, ("too large (%d > %d bytes): %s"):format(stat.size, max_bytes, path)
  end

  -- libuv reads in binary mode: the bytes come back exactly as stored (no
  -- "\r\n" collapsing on Windows), like `lib.nvim.fs.read`.
  local fd, open_err = uv.fs_open(path, "r", 438)
  if not fd then
    return nil, "open failed: " .. tostring(open_err or path)
  end
  local fstat = uv.fs_fstat(fd)
  if not fstat or fstat.type ~= "file" or fstat.size > max_bytes then
    uv.fs_close(fd)
    return nil, "not a regular file within the limit: " .. path
  end
  -- one byte more than allowed: seeing it means the file grew past the limit
  local data, read_err = uv.fs_read(fd, max_bytes + 1, 0)
  uv.fs_close(fd)
  if not data then
    return nil, "read failed: " .. tostring(read_err or path)
  end
  if #data > max_bytes then
    return nil, ("too large (> %d bytes): %s"):format(max_bytes, path)
  end
  return data, nil
end
