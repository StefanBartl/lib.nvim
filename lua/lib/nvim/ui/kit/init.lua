---@module 'lib.nvim.ui.kit'
--- Themed, composable UI toolkit for lib.nvim.
---
--- Phase 1 surface: a theme/preset engine, a single-float `surface` primitive,
--- and the `note` component. `setup()` registers user presets and picks the
--- active default. See docs/ROADMAP/UI-KIT-CONCEPT.md for the full design.
---
---   local kit = require("lib.nvim.ui.kit")
---   kit.popup({ type = "note", title = "Saved", message = "Wrote 3 files" })
---   local surf = kit.surface.open({ lines = { "hi" }, theme = "double" })

require("lib.nvim.ui.kit.@types")

local notify = require("lib.nvim.notify").create("[lib.nvim.ui.kit]")
local theme = require("lib.nvim.ui.kit.theme")
local surface = require("lib.nvim.ui.kit.surface")
local layout = require("lib.nvim.ui.kit.layout")
local picker = require("lib.nvim.ui.kit.picker")
local note = require("lib.nvim.ui.kit.note")
local toast = require("lib.nvim.ui.kit.toast")
local input = require("lib.nvim.ui.kit.input")
local select = require("lib.nvim.ui.kit.select")
local prompt = require("lib.nvim.ui.kit.prompt")

local M = {}

M.theme = theme
M.surface = surface
M.layout = layout

--- Register user presets / set the active default preset.
---@param opts? Lib.UI.Kit.SetupOpts
function M.setup(opts)
  theme.setup(opts)
end

--- Open a note popup (title + message).
---@param opts Lib.UI.Kit.NoteOpts
---@return Lib.UI.Kit.Surface|nil
function M.note(opts)
  return note.open(opts)
end

--- Show an ephemeral corner toast.
---@param opts table
---@return Lib.UI.Kit.Surface|nil
function M.toast(opts)
  return toast.open(opts)
end

--- Open a single-line input.
---@param opts table
---@return Lib.UI.Kit.Surface|nil
function M.input(opts)
  return input.open(opts)
end

--- Open a native themed list chooser (single/multi-select).
---@param opts table
function M.select(opts)
  return select.open(opts)
end

--- Ask a question (confirm / text).
---@param opts table
function M.prompt(opts)
  return prompt.open(opts)
end

--- Open an interactive picker (prompt drives the results/preview slots).
---@param opts table
---@return table|nil
function M.picker(opts)
  return picker.open(opts)
end

--- Component dispatch table.
local COMPONENTS = {
  note = note.open,
  toast = toast.open,
  input = input.open,
  select = select.open,
  prompt = prompt.open,
  picker = picker.open,
}

--- Friendly front door: dispatch on `opts.type` (default "note"). Types not yet
--- implemented warn with their planned phase.
---@param opts table
---@return any
function M.popup(opts)
  opts = opts or {}
  local t = opts.type or "note"

  local handler = COMPONENTS[t]
  if handler then
    return handler(opts)
  end

  local planned = {
    menu = "Phase 3",
    progress = "Phase 3",
    confirm = "Phase 4",
  }
  local when = planned[t]
  if when then
    notify.warn(("popup type %q is planned for %s and is not implemented yet"):format(t, when))
  else
    notify.error(("unknown popup type %q"):format(tostring(t)))
  end
  return nil
end

---@type Lib.UI.Kit
return M
