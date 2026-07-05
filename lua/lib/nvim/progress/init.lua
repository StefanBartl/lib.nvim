---@module 'lib.nvim.progress'
---Cross-platform progress indicator, decoupled from any single UI.
---
---Usage: >lua
---
---  local h = require("lib.nvim.progress").create({ title = "[replacer]" })
---  h:update({ text = "searching", current = 12, total = 128 })
---  h:finish("128 matches in 19 files")
---
---`style` ("auto" | "notify" | "statusline" | "fidget" | "float") only changes
---*how* the same calls render; callers never touch a style implementation
---directly. See `lib.nvim.progress.styles.*` to add a new renderer.
---
---The "float" style owns an interactive window: focus it deliberately and
---press <Esc> (normal mode) to ask for cancellation via `request_cancel()`.
---Since that keymap is buffer-local, nothing happens while any other window
---is focused — the operation is never interrupted by accident.
---
---A handle stays invisible until `delay_ms` has elapsed (default 150ms), so a
---fast operation never flashes UI. If `finish`/`cancel` runs before that,
---nothing is ever rendered.
---
---Only `vim.uv`/`vim.api`/`vim.notify` are used — no OS-specific calls, so
---this behaves identically on Linux, macOS and Windows.

require("lib.nvim.progress.@types")

local resolve_style = require("lib.nvim.progress.resolve_style")
local notify = require("lib.nvim.notify").create("[lib.nvim.progress]")

local M = {}

local DEFAULT_DELAY_MS = 150

---@param prefix string|nil
---@return string
local function normalize_title(prefix)
  if type(prefix) ~= "string" or prefix == "" then
    return ""
  end
  if not prefix:match("%s$") then
    return prefix .. " "
  end
  return prefix
end

---Safely stop+close a uv timer exactly once (same idempotent pattern as
---`lib.nvim.buf_win_tab.capture`).
---@param t uv.uv_timer_t|nil
local function safe_close_timer(t)
  if not t then
    return
  end
  t:stop()
  local uv = vim.uv or vim.loop
  if not uv.is_closing(t) then
    t:close()
  end
end

---@param opts? Lib.Progress.Opts
---@return Lib.Progress.Handle
function M.create(opts)
  opts = opts or {}
  local title = normalize_title(opts.title)
  local delay_ms = type(opts.delay_ms) == "number" and opts.delay_ms or DEFAULT_DELAY_MS
  local style = resolve_style(opts.style or "auto")

  ---@type Lib.Progress.Fields
  local fields = {}
  local style_state = nil
  local started = false
  local done = false
  ---@type fun()[]
  local on_cancel_fns = {}
  local timer = nil ---@type uv.uv_timer_t|nil
  local handle ---@type Lib.Progress.Handle forward-declared: styles may call handle:request_cancel()

  ---@return Lib.Progress.Spec
  local function spec()
    return { title = title, text = fields.text, current = fields.current, total = fields.total }
  end

  local function do_start()
    if started or done then
      return
    end
    started = true
    style_state = style.start(spec(), opts, function() handle:request_cancel() end)
  end

  if delay_ms > 0 then
    local uv = vim.uv or vim.loop
    timer = uv.new_timer()
    if timer then
      timer:start(
        delay_ms,
        0,
        vim.schedule_wrap(function()
          safe_close_timer(timer)
          do_start()
        end)
      )
    else
      do_start()
    end
  else
    do_start()
  end

  handle = {
    cancelled = false,

    update = function(_, new_fields)
      if done then
        return
      end
      new_fields = new_fields or {}
      if new_fields.text ~= nil then
        fields.text = new_fields.text
      end
      if new_fields.current ~= nil then
        fields.current = new_fields.current
      end
      if new_fields.total ~= nil then
        fields.total = new_fields.total
      end
      if started then
        style_state = style.update(style_state, spec(), opts)
      end
    end,

    finish = function(_, text)
      if done then
        return
      end
      done = true
      safe_close_timer(timer)
      if text ~= nil then
        fields.text = text
      end
      if not started then
        return -- never became visible; a fast operation stays silent
      end
      style.finish(style_state, spec(), opts)
    end,

    cancel = function(_, text)
      if done then
        return
      end
      done = true
      safe_close_timer(timer)
      if text ~= nil then
        fields.text = text
      end
      if not started then
        return
      end
      style.cancel(style_state, spec(), opts)
    end,

    on_cancel = function(_, fn)
      on_cancel_fns[#on_cancel_fns + 1] = fn
    end,

    request_cancel = function(self)
      if self.cancelled then
        return
      end
      self.cancelled = true
      for _, fn in ipairs(on_cancel_fns) do
        local ok, err = pcall(fn)
        if not ok then
          notify.error("on_cancel callback failed: " .. tostring(err))
        end
      end
      self:cancel()
    end,
  }

  return handle
end

---@type Lib.Progress
return M
