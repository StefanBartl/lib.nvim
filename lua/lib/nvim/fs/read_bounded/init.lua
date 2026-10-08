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
---```

local uv = vim.uv or vim.loop

---@param path string
---@param max_bytes integer
---@return string|nil content
---@return string|nil err
return function(path, max_bytes)
  local stat = uv.fs_stat(path)
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
