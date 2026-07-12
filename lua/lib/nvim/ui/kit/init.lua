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
local note = require("lib.nvim.ui.kit.note")

local M = {}

M.theme = theme
M.surface = surface

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

--- Friendly front door: dispatch on `opts.type`. Phase 1 implements "note";
--- the remaining component types are recognized but not yet built.
---@param opts table
---@return any
function M.popup(opts)
  opts = opts or {}
  local t = opts.type or "note"

  if t == "note" then
    return note.open(opts)
  end

  local planned = {
    toast = "Phase 2",
    prompt = "Phase 2",
    input = "Phase 2",
    select = "Phase 2",
    menu = "Phase 3",
    progress = "Phase 3",
    confirm = "Phase 4",
    picker = "Phase 3",
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
