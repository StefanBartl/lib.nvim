---@module 'lib.lua.patterns.command'
--- Command: an action as data, with undo and redo.
---
--- A command is `{ name, run = fn(...) -> undo_state, undo = fn(undo_state, ...) }`. `run` returns
--- whatever `undo` needs to take the effect back (the old value, a snapshot). A history executes commands
--- and keeps the undo and redo stacks.
---
--- ```lua
--- local command = require("lib.lua.patterns.command")
--- local h = command.history({ limit = 100 })
--- local set_title = {
---   name = "set title",
---   run = function(buf, title) local old = get(buf); put(buf, title); return old end,
---   undo = function(old, buf) put(buf, old) end,
--- }
--- h:run(set_title, 1, "New")
--- h:undo()  -- back to the old title
--- h:redo()
--- ```
---
--- For `:Command <sub>` routing of user commands see `lib.nvim.bindings.usercmd.composer`.

require("lib.lua.patterns.command.@types")

local M = {}

local unpack = table.unpack or unpack

---@class Lib.Patterns.CommandHistory
local H = {}
H.__index = H

---@param opts { limit: integer|nil }|nil
---@return Lib.Patterns.CommandHistory
function M.history(opts)
  return setmetatable({ limit = opts and opts.limit or 100, undo_stack = {}, redo_stack = {} }, H)
end

local function pack(...)
  return { n = select("#", ...), ... }
end

---Execute `cmd` with `...`. A failing `run` raises and records nothing. Clears the redo stack.
---@param cmd Lib.Patterns.Command
---@param ... any
---@return any undo_state
function H:run(cmd, ...)
  local state = cmd.run(...)
  self.undo_stack[#self.undo_stack + 1] = { cmd = cmd, args = pack(...), state = state }
  if #self.undo_stack > self.limit then
    table.remove(self.undo_stack, 1)
  end
  self.redo_stack = {}
  return state
end

---@return boolean
function H:can_undo()
  return #self.undo_stack > 0
end

---@return boolean
function H:can_redo()
  return #self.redo_stack > 0
end

---Take the last command back. Returns its name or `nil` when there is nothing to undo.
---@return string|nil
function H:undo()
  local entry = table.remove(self.undo_stack)
  if not entry then
    return nil
  end
  if entry.cmd.undo then
    entry.cmd.undo(entry.state, unpack(entry.args, 1, entry.args.n))
  end
  self.redo_stack[#self.redo_stack + 1] = entry
  return entry.cmd.name
end

---Run the last undone command again. Returns its name or `nil`.
---@return string|nil
function H:redo()
  local entry = table.remove(self.redo_stack)
  if not entry then
    return nil
  end
  entry.state = entry.cmd.run(unpack(entry.args, 1, entry.args.n))
  self.undo_stack[#self.undo_stack + 1] = entry
  return entry.cmd.name
end

---Names of the undoable commands, oldest first.
---@return string[]
function H:names()
  local out = {}
  for i, e in ipairs(self.undo_stack) do
    out[i] = e.cmd.name or "?"
  end
  return out
end

function H:clear()
  self.undo_stack, self.redo_stack = {}, {}
end

return M
