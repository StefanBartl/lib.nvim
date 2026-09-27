---@module 'lib.nvim.output.viewer'
---@brief A dump-friendly, stable signature around `lib.nvim.ui.kit.viewer`.
---@description
--- No new window/buffer logic -- `lib.nvim.ui.kit.viewer` already does that.
--- This exists so a `print(...)` migration (dumping arbitrary debug lines)
--- has a stable `title, lines` call shape instead of building an opts table
--- at every call site.

local M = {}

---Opens `lines` in a read-only viewer panel titled `title`.
---@param title string
---@param lines string[]
---@param opts? table Passed through to `ui.kit.viewer.open` (e.g. `width`, `height`, `close_on_focus_lost`)
---@return Lib.UI.Kit.Surface|nil
function M.show_lines(title, lines, opts)
  opts = opts or {}
  return require("lib.nvim.ui.kit.viewer").open(
    vim.tbl_extend("force", opts, { title = title, lines = lines })
  )
end

return M
