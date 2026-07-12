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
local confirm = require("lib.nvim.ui.kit.confirm")
local menu = require("lib.nvim.ui.kit.menu")
local preview = require("lib.nvim.ui.kit.preview")
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

--- Open the live theme playground (config buffer + live-updating gallery).
---@return integer config_buf, integer preview_buf
function M.preview()
  return preview.open()
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

--- Open a button-confirm dialog (horizontal buttons, h/l to move, <CR> confirm).
---@param opts table
---@return Lib.UI.Kit.Surface|nil
function M.confirm(opts)
  return confirm.open(opts)
end

--- Open a cursor-anchored action menu (label → callback).
---@param opts table
---@return Lib.UI.Kit.Surface|nil
function M.menu(opts)
  return menu.open(opts)
end

--- Progress indicator. Thin passthrough to the dedicated `lib.nvim.progress`
--- module (styles: fidget / float / notify / statusline); not reimplemented
--- here. Returns its handle (`:update` / `:finish` / `:cancel`).
---@param opts table
---@return table
function M.progress(opts)
  return require("lib.nvim.progress").create(opts)
end

--- Component dispatch table.
local COMPONENTS = {
  note = note.open,
  toast = toast.open,
  input = input.open,
  select = select.open,
  prompt = prompt.open,
  picker = picker.open,
  confirm = confirm.open,
  menu = menu.open,
  progress = function(opts)
    return require("lib.nvim.progress").create(opts)
  end,
}

--- Friendly front door: dispatch on `opts.type` (default "note"). Supported
--- types: note, toast, input, select, prompt, picker, confirm, menu, progress.
---@param opts table
---@return any
function M.popup(opts)
  opts = opts or {}
  local t = opts.type or "note"

  local handler = COMPONENTS[t]
  if handler then
    return handler(opts)
  end

  notify.error(("unknown popup type %q"):format(tostring(t)))
  return nil
end

-- Register :KitPreview as soon as the kit is loaded, so the playground is
-- reachable without an explicit setup() call.
pcall(preview.ensure_command)

---@type Lib.UI.Kit
return M
