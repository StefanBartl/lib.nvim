---@module 'lib.nvim.ui.kit.shortlist'
--- Promptless, stacked list+preview for short lists that don't need fuzzy
--- search -- a handful of items (marks, recent buffers, ...), not a haystack
--- to filter through a prompt. Preview sits above the results, both full
--- width -- more room for a real file path than the `picker` template's
--- side-by-side columns leave.
---
--- Built on `lib.nvim.ui.kit.chooser` for the results pane -- j/k/arrows wrap-around,
--- <CR> selects, <Esc>/q closes, all for free -- exactly the use its own
--- module doc calls out ("a caller building extra keymaps/behavior on top of
--- current_item()/move() outside of on_select"). The preview is a plain
--- `lib.nvim.ui.kit.surface`, kept in sync via `CursorMoved` on the chooser's buffer,
--- so any way the cursor gets there (keys, mouse, `gg`/`G`) updates it, not
--- just the couple of keys a hand-rolled `move()` would have covered.
---
--- `render(item, surface)` is the same one-contract rendering `lib.nvim.ui.kit.compare`
--- uses: fill `surface:set_lines(...)` for text, or draw directly against
--- `surface.winid`'s geometry for anything else (an image, a diff).

local layout = require("lib.nvim.ui.kit.layout")
local chooser = require("lib.nvim.ui.kit.chooser")
local surface = require("lib.nvim.ui.kit.surface")
local notify = require("lib.nvim.notify").create("[lib.nvim.ui.kit.shortlist]")
local autocmd = require("lib.nvim.bindings.autocmd")

local api = vim.api

local M = {}

--- Open a promptless, stacked list+preview.
---@param opts table  # { items, format_item?(item, width)->string, render(item, surface), on_submit?(item, idx), on_close?(), title?, preview_title?, preview_filetype?, preview_bo?, theme?, initial_index?, spec? }
---@return table|nil handle  # { close(), current_item(), current_index(), results, preview }
function M.open(opts)
  opts = opts or {}
  local items = opts.items
  if type(items) ~= "table" or #items == 0 then
    notify.error("shortlist: `items` is required and must be non-empty")
    return nil
  end
  local render = opts.render
  if type(render) ~= "function" then
    notify.error("shortlist: opts.render(item, surface) is required")
    return nil
  end
  local format_item = opts.format_item or function(item, _width)
    return tostring(item)
  end
  local on_submit = opts.on_submit or function(_item, _idx) end

  local spec = vim.deepcopy(layout.templates.shortlist.spec)
  if type(opts.spec) == "table" then
    spec = vim.tbl_deep_extend("force", spec, opts.spec)
  end
  local geo = layout.compute(spec)
  if not (geo.slots.preview and geo.slots.results) then
    notify.error("shortlist: layout template is missing the preview/results slots")
    return nil
  end

  local preview_surf = surface.open(vim.tbl_extend("force", geo.slots.preview, {
    theme = opts.theme,
    filetype = opts.preview_filetype,
    title = opts.preview_title or "preview",
    bo = opts.preview_bo,
  }))
  if not preview_surf then
    return nil
  end

  local chooser_items = {}
  for i, raw in ipairs(items) do
    chooser_items[i] = { lines = { format_item(raw, geo.slots.results.width) }, data = raw }
  end

  local results_surf = chooser.open({
    items = chooser_items,
    relative = geo.slots.results.relative,
    row = geo.slots.results.row,
    col = geo.slots.results.col,
    width = geo.slots.results.width,
    height = geo.slots.results.height,
    theme = opts.theme,
    title = opts.title,
    initial_index = opts.initial_index,
    on_select = function(picked, idx)
      on_submit(picked.data, idx)
    end,
  })
  if not results_surf then
    preview_surf:close()
    return nil
  end

  -- `chooser.open` already closed any previously open chooser (single active
  -- instance); a bare `q`/`<Esc>`/click-away closes ONLY the results window,
  -- so the preview pane must be torn down from the same lifecycle, not left
  -- to linger behind it -- and this also covers the on_select path above,
  -- since `deliver()` closes the results surface before that callback runs.
  results_surf:on_close(function()
    preview_surf:close()
  end)
  if opts.on_close then
    results_surf:on_close(opts.on_close)
  end

  local function render_current()
    local entry = chooser.current_item()
    if entry and preview_surf:is_valid() then
      pcall(render, entry.data, preview_surf)
    end
  end
  render_current()

  local sync_group = autocmd.group("lib_kit_shortlist_" .. results_surf.winid, true)
  autocmd.create("CursorMoved", render_current, {
    group = sync_group,
    buffer = results_surf.bufnr,
    desc = "lib.nvim.ui.kit.shortlist: keep the preview in sync with the selection",
  })
  autocmd.create("VimResized", function()
    local g = layout.compute(spec)
    if results_surf:is_valid() then
      pcall(api.nvim_win_set_config, results_surf.winid, g.slots.results)
      -- Re-run format_item at the new width too, not just reposition the
      -- window: a caller's format_item (e.g. sessions.nvim's marks menu)
      -- budgets a truncated path against the width it was given, so a
      -- resize that grows the window must re-format to actually show more
      -- of the path, and a resize that shrinks it must re-truncate rather
      -- than leave a line wider than the new window. One line per item
      -- both before and after, so this never disturbs chooser's own row
      -- bookkeeping or the current selection.
      local new_lines = {}
      for i, raw in ipairs(items) do
        new_lines[i] = format_item(raw, g.slots.results.width)
      end
      results_surf:set_lines(new_lines)
    end
    if preview_surf:is_valid() then
      pcall(api.nvim_win_set_config, preview_surf.winid, g.slots.preview)
    end
  end, {
    group = sync_group,
    desc = "lib.nvim.ui.kit.shortlist: keep the list sized to the editor",
  })
  results_surf:on_close(function()
    pcall(api.nvim_del_augroup_by_id, sync_group)
  end)

  return {
    close = function()
      results_surf:close()
    end,
    current_item = function()
      local entry = chooser.current_item()
      return entry and entry.data or nil
    end,
    current_index = chooser.current_index,
    results = results_surf,
    preview = preview_surf,
  }
end

return M
