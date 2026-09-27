---@module 'lib.nvim.notify.internal.fast_event'
---@brief Fast-event reentry guard, shared by `popup.lua` and `lib.nvim.echo`.
---@description
--- `vim.fn`/`nvim_*` calls raise when made from a fast event (a libuv
--- callback, e.g. inside `vim.uv.new_timer():start(...)`). Both delivery
--- paths in this namespace need the same fix: reschedule onto the main loop
--- instead of failing. `M.guard(fn)` wraps `fn` once so every caller gets
--- that behavior without repeating the `vim.in_fast_event()` check.
---
--- Internal to `lib.nvim.notify`/`lib.nvim.echo` -- not part of either
--- module's public surface.

local M = {}

---Wraps `fn` so a call made from a fast event is rescheduled onto the main
---loop (via `vim.schedule`) instead of running -- and possibly raising --
---there directly. A call already on the main loop runs `fn` immediately,
---synchronously, with no scheduling overhead.
---@generic F: function
---@param fn F
---@return F
function M.guard(fn)
  local wrapped
  wrapped = function(...)
    if vim.in_fast_event() then
      local n = select("#", ...)
      local args = { ... }
      vim.schedule(function()
        wrapped(unpack(args, 1, n))
      end)
      return
    end
    return fn(...)
  end
  return wrapped
end

return M
