---@module 'lib.nvim.ui.kit.select'
--- Select component. Backed by the native themed chooser
--- (lib.nvim.ui.kit.chooser), which absorbed and replaced the former
--- lib.nvim.ui.hover_select module (now removed; see UI-KIT-CONCEPT.md §10).

local chooser = require("lib.nvim.ui.kit.chooser")

local M = {}

--- Open a list chooser.
---@param opts table  # { selection|items, on_select, title|message, multi, relative, theme, width, height }
---@return Lib.UI.Kit.Surface|nil
function M.open(opts)
  opts = opts or {}
  return chooser.open({
    items = opts.selection or opts.items or {},
    on_select = opts.on_select or function() end,
    multi_select = opts.multi or opts.multi_select or false,
    title = opts.title or opts.message,
    relative = opts.relative,
    theme = opts.theme,
    width = opts.width,
    height = opts.height,
  })
end

return M
