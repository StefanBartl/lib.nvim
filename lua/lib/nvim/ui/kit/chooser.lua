---@module 'lib.nvim.ui.kit.chooser'
--- Native themed list chooser. Built on the kit surface; replaces the Phase-2
--- delegation to lib.nvim.ui.hover_select and is a superset of
--- `Lib.HoverSelect.Options`, so hover_select can shim over it with no feature
--- gaps (see docs/ROADMAP/UI-KIT-CONCEPT.md §10).
---
--- Navigation matches the original hover_select: j/k/arrows move (wrap-around),
--- <CR> selects, <Esc>/q close, h/l (and other horizontal motions) blocked;
--- in multi-select, <Tab>/<S-Tab> toggle. Selection uses the theme's
--- `KitSelection` (current line) and `KitAccent` (marked lines) groups.
---
--- Items are plain strings (one buffer line each) by default, or "rich"
--- tables — `{ lines = {...}, highlights? = {...}, anchor? = 0 }` — for a
--- multi-line entry with per-column highlight groups (see
--- docs/ROADMAP/UI-KIT-CONCEPT.md §13b). Navigation moves by logical item,
--- not raw buffer line, so this is transparent to plain-string callers
--- (every item is 1 line, anchor 0 — identical to the old behavior).

local surface = require("lib.nvim.ui.kit.surface")
local map = require("lib.nvim.map")
local notify = require("lib.nvim.notify").create("[lib.nvim.ui.kit.chooser]")

local api = vim.api

local M = {}

--- Horizontal motions blocked so the cursor stays on whole rows.
local HORIZONTAL = { "h", "l", "<Left>", "<Right>", "0", "^", "$", "w", "e", "b", "W", "E", "B" }

--- Single active chooser (mirrors hover_select's single-instance model).
local state = {
  surf = nil,
  items = {}, -- raw items as passed in opts.items (strings and/or rich tables)
  entries = {}, -- normalized: { value, lines, highlights, start_row, end_row, anchor_row } (0-based rows)
  on_select = nil,
  multi = false,
  selections = {}, -- keyed by 1-based item index
  ns = api.nvim_create_namespace("lib_kit_chooser"), -- selection marks
  content_ns = api.nvim_create_namespace("lib_kit_chooser_content"), -- per-item custom highlights
}

---@return boolean
function M.is_open()
  return state.surf ~= nil and state.surf:is_valid()
end

--- Normalize one raw item (string or rich table) into an entry, without row
--- offsets yet (those are assigned in a second pass once every item's line
--- count is known).
---@param item any
---@return table entry
local function normalize_item(item)
  if type(item) == "table" and type(item.lines) == "table" then
    return {
      value = item,
      lines = item.lines,
      highlights = item.highlights,
      anchor_row = item.anchor or 0,
    }
  end
  return {
    value = item,
    lines = { tostring(item) },
    highlights = nil,
    anchor_row = 0,
  }
end

--- Build `state.entries` (with row offsets) and the flattened buffer lines
--- from `items`.
---@param items any[]
---@return table[] entries, string[] flat_lines
local function build_entries(items)
  local entries = {}
  local flat = {}
  local row = 0 -- 0-based, next free buffer row
  for i, item in ipairs(items) do
    local e = normalize_item(item)
    e.start_row = row
    for _, l in ipairs(e.lines) do
      flat[#flat + 1] = l
    end
    row = row + #e.lines
    e.end_row = row - 1
    entries[i] = e
  end
  return entries, flat
end

--- Resolve the logical (1-based) item index containing 0-based buffer `row`.
---@param row0 integer
---@return integer|nil
local function item_at_row(row0)
  for i, e in ipairs(state.entries) do
    if row0 >= e.start_row and row0 <= e.end_row then
      return i
    end
  end
  return nil
end

--- Paint every entry's custom highlight spans (once, at open time — entries
--- never change after that, unlike selection marks which toggle).
local function render_content_highlights()
  local buf = state.surf and state.surf.bufnr
  if not buf or not api.nvim_buf_is_valid(buf) then
    return
  end
  api.nvim_buf_clear_namespace(buf, state.content_ns, 0, -1)
  for _, e in ipairs(state.entries) do
    if e.highlights then
      for _, h in ipairs(e.highlights) do
        local row = e.start_row + (h.line or 0)
        local col_start = h.col_start or 0
        local col_end = h.col_end
        if not col_end then
          local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
          col_end = #line
        end
        pcall(api.nvim_buf_set_extmark, buf, state.content_ns, row, col_start, {
          end_col = col_end,
          hl_group = h.hl_group,
        })
      end
    end
  end
end

local function clear_marks()
  if state.surf and api.nvim_buf_is_valid(state.surf.bufnr) then
    api.nvim_buf_clear_namespace(state.surf.bufnr, state.ns, 0, -1)
  end
end

--- Repaint multi-select marks from `state.selections`. A marked item's whole
--- row span is highlighted, not just its anchor row.
local function render_marks()
  clear_marks()
  local buf = state.surf and state.surf.bufnr
  if not buf or not api.nvim_buf_is_valid(buf) then
    return
  end
  for idx, selected in pairs(state.selections) do
    local e = state.entries[idx]
    if selected and e then
      for row = e.start_row, e.end_row do
        pcall(api.nvim_buf_set_extmark, buf, state.ns, row, 0, {
          line_hl_group = "KitAccent",
          hl_eol = true,
        })
      end
    end
  end
end

--- Close the chooser and reset state (idempotent).
function M.close()
  if state.surf then
    clear_marks()
    state.surf:close()
  end
  state.surf = nil
  state.items = {}
  state.entries = {}
  state.on_select = nil
  state.multi = false
  state.selections = {}
end

--- Move the current selection by `delta` items, wrapping around. Reusable by
--- the picker prompt (Part B) to drive a results slot.
---@param delta integer
function M.move(delta)
  if not M.is_open() then
    return
  end
  local win = state.surf.winid
  local count = #state.entries
  if count == 0 then
    return
  end
  local cur_row0 = api.nvim_win_get_cursor(win)[1] - 1
  local cur_idx = item_at_row(cur_row0) or 1
  local idx = cur_idx + delta
  if idx < 1 then
    idx = count
  elseif idx > count then
    idx = 1
  end
  local e = state.entries[idx]
  api.nvim_win_set_cursor(win, { e.start_row + e.anchor_row + 1, 0 })
end

--- 1-based logical item index at the cursor, or nil when closed.
---@return integer|nil
function M.current_index()
  if not M.is_open() then
    return nil
  end
  local row0 = api.nvim_win_get_cursor(state.surf.winid)[1] - 1
  return item_at_row(row0)
end

--- Toggle the current item's mark (multi-select). Also drivable by the picker.
function M.toggle()
  if not M.is_open() then
    return
  end
  local idx = M.current_index()
  if not idx then
    return
  end
  state.selections[idx] = not state.selections[idx]
  render_marks()
end

--- Resolve the selection, fire the callback, then close. Also drivable by the
--- picker prompt (Part B) to submit the highlighted item.
function M.submit()
  if not M.is_open() then
    return
  end
  local idx = M.current_index()
  local cb, multi, entries = state.on_select, state.multi, state.entries

  if multi then
    local idxs = {}
    for i, selected in pairs(state.selections) do
      if selected and entries[i] then
        idxs[#idxs + 1] = i
      end
    end
    table.sort(idxs)
    if #idxs == 0 and idx then
      idxs = { idx }
    end
    local chosen = {}
    for _, i in ipairs(idxs) do
      chosen[#chosen + 1] = entries[i].value
    end
    M.close()
    if cb and #chosen > 0 then
      cb(chosen, idxs)
    end
  else
    local entry = idx and entries[idx]
    M.close()
    if cb and entry ~= nil then
      cb(entry.value, idx)
    end
  end
end

--- Open a chooser.
---@param opts table  # { items, on_select, multi_select?, title?, relative?, width?, height?, theme? }
---@return Lib.UI.Kit.Surface|nil
function M.open(opts)
  if not opts or type(opts.items) ~= "table" or #opts.items == 0 then
    notify.error("chooser: `items` is required and must be non-empty")
    return nil
  end
  if type(opts.on_select) ~= "function" then
    notify.error("chooser: `on_select` callback is required")
    return nil
  end

  M.close()

  local entries, flat_lines = build_entries(opts.items)

  local surf = surface.open({
    lines = flat_lines,
    theme = opts.theme,
    title = opts.title,
    relative = opts.relative or "cursor",
    width = opts.width,
    height = opts.height or #flat_lines,
    enter = true,
    filetype = "lib-kit-chooser",
    wo = { cursorline = true },
  })
  if not surf then
    return nil
  end

  -- Map the current line to the theme's selection highlight.
  local cur = api.nvim_get_option_value("winhighlight", { win = surf.winid })
  local sep = cur ~= "" and "," or ""
  pcall(
    api.nvim_set_option_value,
    "winhighlight",
    cur .. sep .. "CursorLine:KitSelection",
    { win = surf.winid }
  )

  state.surf = surf
  state.items = opts.items
  state.entries = entries
  state.on_select = opts.on_select
  state.multi = opts.multi_select or opts.multi or false
  state.selections = {}

  render_content_highlights()

  local mo = { buffer = surf.bufnr, nowait = true }
  for _, key in ipairs(HORIZONTAL) do
    map("n", key, "<Nop>", mo)
  end
  map("n", "<CR>", M.submit, mo)
  map("n", "<2-LeftMouse>", M.submit, mo)
  map("n", "<Esc>", M.close, mo)
  map("n", "q", M.close, mo)
  if state.multi then
    map("n", "<Tab>", M.toggle, mo)
    map("n", "<S-Tab>", function()
      M.toggle()
      M.move(-1)
    end, mo)
  end

  if surf:is_valid() and entries[1] then
    api.nvim_win_set_cursor(surf.winid, { entries[1].start_row + entries[1].anchor_row + 1, 0 })
  end

  return surf
end

return M
