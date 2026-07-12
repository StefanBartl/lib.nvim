---@module 'lib.nvim.ui.hover_select'
--- Compatibility shim. The hover-select chooser has been absorbed into
--- `lib.nvim.ui.kit.chooser` (see docs/ROADMAP/UI-KIT-CONCEPT.md §10). This
--- module keeps the original public API — `open` / `close` / `is_open` and the
--- `Lib.HoverSelect.Options` shape — so the existing call sites across the
--- author's plugins keep working unchanged while the implementation now lives in
--- the kit. Migrate call sites to `require("lib.nvim.ui.kit").select` at leisure.

require("lib.nvim.ui.hover_select.@types")

local chooser = require("lib.nvim.ui.kit.chooser")

local M = {}

--- Open a hover-select window.
---@param opts Lib.HoverSelect.Options
---@return integer|nil bufnr
---@return integer|nil winid
function M.open(opts)
  opts = opts or {}
  local surf = chooser.open({
    items = opts.items,
    on_select = opts.on_select,
    multi_select = opts.multi_select,
    title = opts.title,
    relative = opts.relative,
    width = opts.width,
    height = opts.height,
    -- buf_options / win_options / auto_width / use_tab_navigation are accepted
    -- for signature compatibility; the kit chooser themes and auto-sizes itself.
  })
  if not surf then
    return nil, nil
  end
  return surf.bufnr, surf.winid
end

--- Close the active chooser.
function M.close()
  chooser.close()
end

--- Whether a chooser is currently open.
---@return boolean
function M.is_open()
  return chooser.is_open()
end

---@type Lib.UI.HoverSelect
return M
