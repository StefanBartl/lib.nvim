---@module 'lib.nvim.window.center'
---Recenter a floating window on the editor.
---
---Only floating windows can be repositioned this way; for any other window this
---is a safe no-op. Uses the float's current width/height and the editor size to
---compute a centered `row`/`col`.

require("lib.nvim.window.@types")

local api = vim.api
local notify = require("lib.nvim.notify").create("[lib.nvim.window.center]")

---@param winid integer
---@return boolean ok true when the window was recentered
local function center(winid)
  if not api.nvim_win_is_valid(winid) then
    notify.debug(string.format("invalid window id: %s", tostring(winid)))
    return false
  end

  local ok, cfg = pcall(api.nvim_win_get_config, winid)
  if not ok or not cfg then
    return false
  end

  if cfg.relative == nil or cfg.relative == "" then
    notify.debug("center: target is not a floating window; ignoring")
    return false
  end

  local width = cfg.width
  local height = cfg.height
  if type(width) ~= "number" or type(height) ~= "number" then
    return false
  end

  local row = math.max(0, math.floor((vim.o.lines - height) / 2 - 1))
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))

  -- Re-anchor on the editor; `relative` is required when setting row/col.
  local patch = { relative = "editor", row = row, col = col }
  return pcall(api.nvim_win_set_config, winid, patch) == true
end

return center
