---@module 'lib.nvim.debounce.buffer'
--- Buffer-scoped debounce: one independent timer per `bufnr`.
---
--- `M.new(fn, opts)` returns a handle `{ call, cancel, cancel_all }`. Each
--- `call(bufnr, ...)` resets that buffer's timer; when it fires, `fn(bufnr,
--- ...)` runs with the arguments from the most recent `call` for that
--- buffer, scheduled via `vim.schedule`. When `opts.adaptive` is set the
--- effective delay grows with the buffer's line count, so debouncing large
--- buffers (e.g. for expensive highlighting) backs off automatically.
---
--- A buffer-local autocmd on `opts.cleanup_events` (default `BufDelete`,
--- `BufWipeout`) cancels and forgets a buffer's timer the moment it goes
--- away, so timers never outlive their buffer.
---
--- Usage:
--- ```lua
--- local debounce_buffer = require("lib.nvim.debounce.buffer")
--- local d = debounce_buffer.new(function(bufnr)
---   vim.notify("re-highlighted buf " .. bufnr)
--- end, { ms = 150, adaptive = true })
---
--- d.call(bufnr)       -- schedules a run ~150ms out (more for big buffers)
--- d.cancel(bufnr)      -- cancel just this buffer's pending run
--- d.cancel_all()        -- cancel every tracked buffer
--- ```

require("lib.nvim.debounce.@types")

local uv = vim.uv or vim.loop
local api = vim.api

local DEFAULT_MS = 200
local DEFAULT_CLEANUP_EVENTS = { "BufDelete", "BufWipeout" }

---Create a buffer-scoped debounced-call handle around `fn`.
---@param fn fun(bufnr:integer, ...:any)
---@param opts? Lib.Debounce.BufferOpts
---@return Lib.Debounce.BufferHandle
local function new(fn, opts)
  opts = opts or {}
  local ms = opts.ms or DEFAULT_MS
  local adaptive = opts.adaptive or false
  local cleanup_events = opts.cleanup_events or DEFAULT_CLEANUP_EVENTS

  ---@type table<integer, userdata>
  local timers = {}
  ---@type table<integer, boolean>
  local watched = {}

  local function close_timer(bufnr)
    local timer = timers[bufnr]
    if timer then
      pcall(timer.stop, timer)
      pcall(timer.close, timer)
      timers[bufnr] = nil
    end
  end

  local function cancel(bufnr)
    close_timer(bufnr)
  end

  local function cancel_all()
    for bufnr in pairs(timers) do
      close_timer(bufnr)
    end
  end

  ---@param bufnr integer
  local function ensure_cleanup_autocmd(bufnr)
    if watched[bufnr] then
      return
    end
    watched[bufnr] = true
    pcall(api.nvim_create_autocmd, cleanup_events, {
      buffer = bufnr,
      callback = function()
        cancel(bufnr)
        watched[bufnr] = nil
      end,
    })
  end

  ---@param bufnr integer
  ---@return integer
  local function effective_delay(bufnr)
    if not adaptive then
      return ms
    end
    local ok, line_count = pcall(api.nvim_buf_line_count, bufnr)
    if not ok then
      return ms
    end
    return math.min(ms * 4, ms + math.floor(line_count / 50))
  end

  ---@param bufnr integer
  ---@param ... any
  local function call(bufnr, ...)
    local args = { ... }
    local n = select("#", ...)

    ensure_cleanup_autocmd(bufnr)

    local timer = timers[bufnr]
    if not timer then
      timer = uv.new_timer()
      timers[bufnr] = timer
    else
      pcall(timer.stop, timer)
    end

    local delay = effective_delay(bufnr)
    timer:start(delay, 0, function()
      vim.schedule(function()
        fn(bufnr, unpack(args, 1, n))
      end)
    end)
  end

  return { call = call, cancel = cancel, cancel_all = cancel_all }
end

return { new = new }
