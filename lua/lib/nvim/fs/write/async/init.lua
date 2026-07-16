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

---@param path string
---@param content string
---@param cb fun(ok: boolean, err: string|nil)
return function(path, content, cb)
  local uv = vim.uv or vim.loop

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

  local function finish(ok, err)
    vim.schedule(function()
      cb(ok, err)
    end)
  end

  -- 438 == 0644 (decimal literal; libuv takes the mode as a number).
  uv.fs_open(path, "w", 438, function(open_err, fd)
    if open_err or not fd then
      finish(false, "open failed: " .. tostring(open_err or path))
      return
    end
    uv.fs_write(fd, content, -1, function(write_err)
      uv.fs_close(fd, function(close_err)
        local err = write_err or close_err
        finish(err == nil, err and tostring(err) or nil)
      end)
    end)
  end)
end
