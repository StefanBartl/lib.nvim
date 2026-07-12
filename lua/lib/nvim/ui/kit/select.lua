---@module 'lib.nvim.ui.kit.select'
--- Select component. Phase 2 delegates to the existing lib.nvim.ui.hover_select
--- (see the absorption plan in docs/ROADMAP/UI-KIT-CONCEPT.md §10); a native
--- themed chooser replaces this in Phase 3 without changing this entry point.

local hover_select = require("lib.nvim.ui.hover_select")

local M = {}

--- Open a list chooser.
---@param opts table  # { selection|items, on_select, title|message, multi, relative }
---@return integer|nil bufnr
---@return integer|nil winid
function M.open(opts)
  opts = opts or {}
  local items = opts.selection or opts.items or {}
  return hover_select.open({
    items = items,
    title = opts.title or opts.message,
    on_select = opts.on_select or function() end,
    multi_select = opts.multi or opts.multi_select or false,
    relative = opts.relative,
  })
end

return M
