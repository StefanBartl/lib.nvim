---@module 'lib.nvim.progress.styles.echo'
---Renders progress as a transient `nvim_echo` cmdline line via `lib.nvim.echo`.
---
---`start`/`update` write with `history = false` (a fast-moving progress line
---has no business in `:messages`); `finish`/`cancel` write once with
---`history = true`, so the operation's final line stays in the log.

require("lib.nvim.progress.@types")

local render_text = require("lib.nvim.progress.internal.render_text")

---@internal
---@param spec Lib.Progress.Spec
---@param history boolean
local function write(spec, history)
  require("lib.nvim.echo").write(render_text(spec), { history = history })
end

---@param spec Lib.Progress.Spec
---@return table state
local function start(spec)
  write(spec, false)
  return {}
end

---@param state table
---@param spec Lib.Progress.Spec
---@return table state
local function update(state, spec)
  write(spec, false)
  return state
end

---@param _state table
---@param spec Lib.Progress.Spec
local function finish(_state, spec)
  write(spec, true)
end

---@param _state table
---@param spec Lib.Progress.Spec
local function cancel(_state, spec)
  write(spec, true)
end

---@type Lib.Progress.StyleImpl
return { start = start, update = update, finish = finish, cancel = cancel }
