---@module 'lib.nvim.fs.write.async'
--- Asynchronous counterpart to `lib.nvim.fs.write.to_file`: creates the
--- parent directory synchronously, then opens/writes/closes the file via
--- libuv without blocking the editor.
---
---   require("lib.nvim.fs.write.async")("/tmp/out.txt", "hello", function(ok, err)
---     if not ok then vim.notify("write failed: " .. tostring(err)) end
---   end)
---
--- `cb` is invoked on the main loop (wrapped in `vim.schedule`), so it is
--- safe to touch `vim.api.*` from inside it.

require("lib.nvim.fs.write.async.@types")

local async = require("lib.nvim.async")

local uv = vim.uv or vim.loop

-- Awaitable forms of the three libuv calls this module chains. The number
-- is each function's full arity including the trailing callback.
local fs_open = async.wrap(uv.fs_open, 4)
local fs_write = async.wrap(uv.fs_write, 4)
local fs_close = async.wrap(uv.fs_close, 2)

---@param path string
---@param content string
---@param cb fun(ok: boolean, err: string|nil)
return function(path, content, cb)
  local dir = vim.fn.fnamemodify(path, ":h")
  if dir == "" then
    vim.schedule(function()
      cb(false, "Invalid directory for path: " .. path)
    end)
    return
  end
  local ok_mkdir, err_mkdir = pcall(vim.fn.mkdir, dir, "p")
  if not ok_mkdir then
    vim.schedule(function()
      cb(false, "mkdir failed: " .. tostring(err_mkdir))
    end)
    return
  end

  async.run(function()
    -- 438 == 0644 (decimal literal; libuv takes the mode as a number).
    local open_err, fd = fs_open(path, "w", 438)
    if open_err or not fd then
      return false, "open failed: " .. tostring(open_err or path)
    end

    local write_err = fs_write(fd, content, -1)
    local close_err = fs_close(fd)

    local err = write_err or close_err
    return err == nil, err and tostring(err) or nil
  end, cb, { tag = "lib.nvim.fs.write.async" })
end
