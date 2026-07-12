---@module 'lib.nvim.ui.kit.menu'
--- Menu component: a cursor-anchored action list. Each item pairs a label with
--- a callback; picking an item runs its callback. Built on the native chooser
--- (lib.nvim.ui.kit.chooser), so it inherits themed selection and the same
--- navigation (j/k/arrows, <CR>, <Esc>/q).

local chooser = require("lib.nvim.ui.kit.chooser")
local notify = require("lib.nvim.notify").create("[lib.nvim.ui.kit.menu]")

local M = {}

--- Open an action menu.
---@param opts table  # { items = { { label, action }, … }, title?, theme?, relative? }
---@return Lib.UI.Kit.Surface|nil
function M.open(opts)
  opts = opts or {}
  local items = opts.items or {}
  if type(items) ~= "table" or #items == 0 then
    notify.error("menu: `items` is required and must be non-empty")
    return nil
  end

  local labels = {}
  for i, it in ipairs(items) do
    if type(it) == "table" then
      labels[i] = it.label or it.text or tostring(it)
    else
      labels[i] = tostring(it)
    end
  end

  return chooser.open({
    items = labels,
    title = opts.title,
    theme = opts.theme,
    relative = opts.relative or "cursor",
    on_select = function(_, idx)
      local it = items[idx]
      local action = type(it) == "table" and (it.action or it.cb) or nil
      if type(action) == "function" then
        action()
      end
    end,
  })
end

return M
