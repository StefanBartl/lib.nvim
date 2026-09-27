---@module 'lib.nvim.echo'
---@brief Transient `nvim_echo` output -- a cmdline-area line, not a popup.
---@description
--- `lib.nvim.notify` (optionally via `popup.lua`) is for discrete events: a
--- toast plus a yankable history. This module is for the other shape of
--- output -- a progress/status line meant to be glanced at and then
--- overwritten, the same thing `:echo`/`:echon` are used for in Vimscript.
--- No history, no toast, no title: just `nvim_echo`.
---
---   local echo = require("lib.nvim.echo")
---   echo.write("searching... 12/128")                  -- transient, no history
---   echo.write("done: 128 matches", { history = true }) -- also lands in :messages
---
--- Fast-event-safe: called from a libuv callback (a timer, an async
--- callback), a write is rescheduled onto the main loop instead of raising
--- -- same reentry guard `lib.nvim.notify.popup` uses, shared via
--- `lib.nvim.notify.internal.fast_event` rather than duplicated here.

require("lib.nvim.echo.@types")

local fast_event = require("lib.nvim.notify.internal.fast_event")

local M = {}

-- Only WARN/ERROR get a highlight when `text_or_chunks` is a plain string --
-- mirrors lib.nvim.notify.popup's MSG_HL, so the two channels read
-- consistently at a glance.
local LEVEL_HL = {
  [vim.log.levels.WARN] = "WarningMsg",
  [vim.log.levels.ERROR] = "ErrorMsg",
}

---@internal
---Normalizes `text_or_chunks` to the chunk list `nvim_echo` expects.
---@param text_or_chunks string|Lib.Echo.Chunk[]
---@param level? integer
---@return Lib.Echo.Chunk[]
local function to_chunks(text_or_chunks, level)
  if type(text_or_chunks) == "table" then
    return text_or_chunks
  end
  local hl = level and LEVEL_HL[level] or nil
  return { { tostring(text_or_chunks), hl } }
end

---Writes a transient (or, with `history = true`, recorded) cmdline-area line.
---@param text_or_chunks string|Lib.Echo.Chunk[]
---@param opts? Lib.Echo.WriteOpts
---@return nil
M.write = fast_event.guard(function(text_or_chunks, opts)
  opts = opts or {}
  local chunks = to_chunks(text_or_chunks, opts.level)
  local history = opts.history == true
  vim.api.nvim_echo(chunks, history, {})
end)

---@type Lib.Echo
return M
