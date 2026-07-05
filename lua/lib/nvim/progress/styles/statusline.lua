---@module 'lib.nvim.progress.styles.statusline'
---Headless renderer: keeps rendered text in memory only, keyed by handle.
---This module never touches the screen — read it from your own statusline
---component.
---
---Usage in a statusline function: >lua
---
---  local sl = require("lib.nvim.progress.styles.statusline")
---  local lines = sl.active()  -- string[], oldest first

require("lib.nvim.progress.@types")

local M = {}

---@type table<table, string>
local text_by_state = {}
---@type table[] insertion order, oldest first
local order = {}

---Nudge Neovim to redraw the statusline. Without this, a component reading
---`active()` only refreshes on the next unrelated redraw (cursor move, mode
---change, …) — a background search would otherwise look frozen while the
---user is idle. Scheduled so this is safe regardless of the caller's context.
local function request_redraw()
  vim.schedule(function()
    pcall(vim.cmd, "redrawstatus")
  end)
end

---@param spec Lib.Progress.Spec
---@return string
local function render_text(spec)
  local parts = {}
  if spec.text and spec.text ~= "" then
    parts[#parts + 1] = spec.text
  end
  if type(spec.current) == "number" then
    if type(spec.total) == "number" and spec.total > 0 then
      parts[#parts + 1] = string.format("(%d/%d)", spec.current, spec.total)
    else
      parts[#parts + 1] = string.format("(%d)", spec.current)
    end
  end
  return spec.title .. table.concat(parts, " ")
end

---@param state table
local function clear(state)
  text_by_state[state] = nil
  for i, s in ipairs(order) do
    if s == state then
      table.remove(order, i)
      break
    end
  end
  request_redraw()
end

---@param spec Lib.Progress.Spec
---@return table state
local function start(spec)
  local state = {}
  order[#order + 1] = state
  text_by_state[state] = render_text(spec)
  request_redraw()
  return state
end

---@param state table
---@param spec Lib.Progress.Spec
---@return table state
local function update(state, spec)
  text_by_state[state] = render_text(spec)
  request_redraw()
  return state
end

---@param state table
local function finish(state)
  clear(state)
end

---@param state table
local function cancel(state)
  clear(state)
end

---Currently active progress texts, oldest first.
---@return string[]
function M.active()
  local out = {}
  for i, state in ipairs(order) do
    out[i] = text_by_state[state]
  end
  return out
end

M.start = start
M.update = update
M.finish = finish
M.cancel = cancel

---@type Lib.Progress.StyleImpl
return M
