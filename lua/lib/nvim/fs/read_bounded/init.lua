---@module 'lib.nvim.fs.read_bounded'
--- Read a file only when it is a regular file of at most `max_bytes` bytes.
---
--- For files that sit in a repository somebody else controls (a `.git/config`
--- in a cloned plugin, a manifest): a FIFO would block the read forever, a
--- device file never ends, a multi-gigabyte file exhausts memory. The check is
--- done on the stat, before the file is opened.
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
  return require("lib.nvim.fs.read")(path)
end
