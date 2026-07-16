---@module 'lib.nvim.debounce'
--- Generic debounce primitive for callbacks.
---
--- `M.new(fn, ms)` returns a handle `{ call, cancel }`: each `call(...)`
--- resets a `ms`-millisecond libuv timer; when it fires, `fn(...)` is
--- invoked with the arguments from the *most recent* `call`, scheduled onto
--- the main loop via `vim.schedule` (libuv timer callbacks run off the main
--- loop in Neovim, so touching `vim.api.*` directly from them is unsafe).
---
--- Usage:
--- ```lua
--- local debounce = require("lib.nvim.debounce")
--- local d = debounce.new(function(text)
---   vim.notify("saved: " .. text)
--- end, 300)
---
--- d.call("a")
--- d.call("ab") -- resets the timer; only this call's args fire
--- -- 300ms later: notify("saved: ab")
---
--- d.cancel() -- stop pending call, safe to call repeatedly
--- ```

require("lib.nvim.debounce.@types")

local uv = vim.uv or vim.loop

local M = {}

---Create a debounced-call handle around `fn`.
---@param fn fun(...:any)
---@param ms integer
---@return Lib.Debounce.Handle
function M.new(fn, ms)
  local timer = nil
  local closed = true

  local function close_timer()
    if timer and not closed then
      closed = true
      pcall(timer.stop, timer)
      pcall(timer.close, timer)
    end
    timer = nil
  end

  ---@param ... any
  local function call(...)
    local args = { ... }
    local n = select("#", ...)

    if not timer or closed then
      timer = uv.new_timer()
      closed = false
    else
      pcall(timer.stop, timer)
    end

    timer:start(ms, 0, function()
      vim.schedule(function()
        fn(unpack(args, 1, n))
      end)
    end)
  end

  local function cancel()
    close_timer()
  end

  return { call = call, cancel = cancel }
end

return M
