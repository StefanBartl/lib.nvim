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

---Like `M.new`, but also tracks how many calls arrived while a previous
---timer was still pending (i.e. got superseded before firing) — useful for
---"N updates coalesced" UI feedback. Upstreamed from reposcope.nvim's
---`utils.protection.debounce_with_counter`.
---@param fn fun(...:any)
---@param ms integer
---@return Lib.Debounce.Handle handle  `handle.call`/`handle.cancel` as in `M.new`
---@return fun(): integer skipped  Number of calls superseded since the last fire
function M.new_with_counter(fn, ms)
  local skipped = 0
  local pending = false

  local handle = M.new(function(...)
    pending = false
    fn(...)
  end, ms)

  local function call(...)
    if pending then
      skipped = skipped + 1
    end
    pending = true
    handle.call(...)
  end

  local function get_skipped()
    return skipped
  end

  return { call = call, cancel = handle.cancel }, get_skipped
end

return M
