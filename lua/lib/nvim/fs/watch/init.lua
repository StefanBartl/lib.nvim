---@module 'lib.nvim.fs.watch'
--- Generic "watch this path, debounced, call me on change" primitive.
--- `uv.new_fs_event()` plus `lib.nvim.debounce`: a single filesystem change
--- can fire the raw callback several times in quick succession (an editor
--- doing a save-via-rename, a build tool touching several files at once),
--- so the raw event feeds a debounce handle instead of calling `on_change`
--- directly.
---
--- `start()` returns once libuv accepted the handle, not once the OS backend is
--- delivering events: on macOS libuv registers the FSEvents stream from its own
--- run-loop thread, so a change made in the first milliseconds after `start()`
--- (most visibly under load, on the first watcher of a process) may never be
--- reported. Code that must not miss a change made right after `start()` has to
--- confirm the watcher is live first (see TESTS/watch_spec.lua).
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
---
--- A watcher can also fail after it started (the watched directory is removed,
--- EPERM, the inotify limit): libuv then reports the error through the event
--- callback and usually stops delivering. `opts.on_error(err, path)` is called
--- for it (scheduled, so editor APIs are usable) and `handle.last_error()`
--- returns the latest one; a caller that must not miss changes falls back to a
--- full scan there.

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

  local stopped = false
  local last_error ---@type string|nil

  -- libuv reports a failed start (e.g. ENOENT for a missing path) as a
  -- `nil, err` return, not by raising -- so the return value has to be read,
  -- or a watcher on a path that does not exist looks like a live one.
  local start_ok, start_res, start_err = pcall(
    ev.start,
    ev,
    path,
    { recursive = opts.recursive or false },
    function(cb_err, filename, events)
      if cb_err then
        -- A failing backend (watched directory removed, EPERM, inotify limit
        -- reached) used to vanish here, leaving a watcher that looks live and
        -- never fires again. Keep the error and hand it to the caller.
        last_error = tostring(cb_err)
        if opts.on_error then
          local msg = last_error
          vim.schedule(function()
            if not stopped then
              opts.on_error(msg, path)
            end
          end)
        end
        return
      end
      d.call(filename, events)
    end
  )
  if not start_ok or start_res == nil then
    pcall(ev.close, ev)
    d.cancel()
    -- `pcall` puts a thrown message in `start_res`; libuv's own refusal is `nil, err`.
    local why = start_ok and start_err or start_res
    return nil,
      "fs_event start failed for path: " .. path .. (why and (" (" .. tostring(why) .. ")") or "")
  end

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

  return {
    stop = stop,
    last_error = function()
      return last_error
    end,
  }, nil
end

---@type Lib.Fs.Watch
return M
