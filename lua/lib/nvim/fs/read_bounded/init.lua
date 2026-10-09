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
  if
    type(path) ~= "string"
    or type(max_bytes) ~= "number"
    or max_bytes ~= max_bytes -- NaN
    or max_bytes < 0
    or max_bytes == math.huge
  then
    return nil, "invalid arguments"
  end
  max_bytes = math.floor(max_bytes)
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
  -- "\r\n" collapsing on Windows). O_NONBLOCK: a FIFO swapped in after the stat
  -- must not block the open; O_NOFOLLOW: neither may a symlink when the caller
  -- refused those (both constants are absent on Windows).
  local c = uv.constants
  local flags = c.O_RDONLY + (c.O_NONBLOCK or 0) + ((not follow and c.O_NOFOLLOW) or 0)
  local fd, open_err = uv.fs_open(path, flags, 438)
  if not fd then
    return nil, "open failed: " .. tostring(open_err or path)
  end
  local fstat = uv.fs_fstat(fd)
  if not fstat or fstat.type ~= "file" or fstat.size > max_bytes then
    uv.fs_close(fd)
    return nil, "not a regular file within the limit: " .. path
  end

  -- In blocks, so that only what is there is allocated (not the cap) and a short
  -- read does not pass for the end of the file. One byte past the cap is asked
  -- for: seeing it means the file grew past the limit.
  local chunks, total = {}, 0
  local ok, err = pcall(function()
    while total <= max_bytes do
      local chunk, read_err = uv.fs_read(fd, math.min(262144, max_bytes + 1 - total), total)
      if not chunk then
        error(read_err or "read failed", 0)
      end
      if chunk == "" then
        break
      end
      chunks[#chunks + 1] = chunk
      total = total + #chunk
    end
  end)
  uv.fs_close(fd)
  if not ok then
    return nil, "read failed: " .. tostring(err)
  end
  if total > max_bytes then
    return nil, ("too large (> %d bytes): %s"):format(max_bytes, path)
  end
  return table.concat(chunks), nil
end
