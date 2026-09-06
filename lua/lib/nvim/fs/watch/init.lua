---@module 'lib.nvim.fs.watch'
--- Generic "watch this path, debounced, call me on change" primitive.
--- `uv.new_fs_event()` plus `lib.nvim.debounce`: a single filesystem change
--- can fire the raw callback several times in quick succession (an editor
--- doing a save-via-rename, a build tool touching several files at once),
--- so the raw event feeds a debounce handle instead of calling `on_change`
--- directly.
---
--- Closing an `fs_event` handle is asynchronous: it may still report itself
--- open for one loop tick after `:close()`, so `stop()` guards with an
--- `is_closing()` check and a `pcall` before closing.
---
---```lua
--- local watch = require("lib.nvim.fs.watch")
---
--- local handle, err = watch.start("/path/to/dir", function(path, filename, events)
---   vim.notify(filename .. " changed under " .. path)
--- end, { debounce_ms = 200 })
---
--- handle.stop() -- safe to call more than once
---```

require("lib.nvim.fs.watch.@types")

local debounce = require("lib.nvim.debounce")
local uv = vim.uv or vim.loop

local M = {}

---Watch `path` (a file or directory) for filesystem changes, debounced.
---@param path string
---@param on_change fun(path: string, filename: string|nil, events: table)
---@param opts? Lib.Fs.Watch.Opts
---@return Lib.Fs.Watch.Handle|nil handle
---@return string|nil err
function M.start(path, on_change, opts)
  opts = opts or {}

  local ev, new_err = uv.new_fs_event()
  if not ev then
    return nil, "uv.new_fs_event() failed: " .. tostring(new_err)
  end

  local d = debounce.new(function(filename, events)
    on_change(path, filename, events)
  end, opts.debounce_ms or 200)

  local start_ok = pcall(function()
    ev:start(path, { recursive = opts.recursive or false }, function(cb_err, filename, events)
      if cb_err then
        return
      end
      d.call(filename, events)
    end)
  end)
  if not start_ok then
    pcall(ev.close, ev)
    return nil, "fs_event start failed for path: " .. path
  end

  local stopped = false
  local function stop()
    if stopped then
      return
    end
    stopped = true
    d.cancel()
    if ev and not ev:is_closing() then
      pcall(ev.stop, ev)
      pcall(ev.close, ev)
    end
  end

  return { stop = stop }, nil
end

---@type Lib.Fs.Watch
return M
