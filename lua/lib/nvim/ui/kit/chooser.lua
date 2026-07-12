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
  items = {},
  on_select = nil,
  multi = false,
  selections = {},
  ns = api.nvim_create_namespace("lib_kit_chooser"),
}

---@return boolean
function M.is_open()
  return state.surf ~= nil and state.surf:is_valid()
end

local function clear_marks()
  if state.surf and api.nvim_buf_is_valid(state.surf.bufnr) then
    api.nvim_buf_clear_namespace(state.surf.bufnr, state.ns, 0, -1)
  end
end

--- Repaint multi-select marks from `state.selections`.
local function render_marks()
  clear_marks()
  local buf = state.surf and state.surf.bufnr
  if not buf or not api.nvim_buf_is_valid(buf) then
    return
  end
  for line, selected in pairs(state.selections) do
    if selected then
      pcall(api.nvim_buf_set_extmark, buf, state.ns, line - 1, 0, {
        line_hl_group = "KitAccent",
        hl_eol = true,
      })
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
  state.on_select = nil
  state.multi = false
  state.selections = {}
end

--- Move the current selection by `delta` rows, wrapping around. Reusable by the
--- picker prompt (Part B) to drive a results slot.
---@param delta integer
function M.move(delta)
  if not M.is_open() then
    return
  end
  local win = state.surf.winid
  local count = api.nvim_buf_line_count(state.surf.bufnr)
  local line = api.nvim_win_get_cursor(win)[1] + delta
  if line < 1 then
    line = count
  elseif line > count then
    line = 1
  end
  api.nvim_win_set_cursor(win, { line, 0 })
end

--- 1-based index of the current row, or nil when closed.
---@return integer|nil
function M.current_index()
  if not M.is_open() then
    return nil
  end
  return api.nvim_win_get_cursor(state.surf.winid)[1]
end

--- Toggle the current row's mark (multi-select). Also drivable by the picker.
function M.toggle()
  if not M.is_open() then
    return
  end
  local line = api.nvim_win_get_cursor(state.surf.winid)[1]
  state.selections[line] = not state.selections[line]
  render_marks()
end

--- Resolve the selection, fire the callback, then close. Also drivable by the
--- picker prompt (Part B) to submit the highlighted item.
function M.submit()
  if not M.is_open() then
    return
  end
  local line = api.nvim_win_get_cursor(state.surf.winid)[1]
  local cb, multi, items = state.on_select, state.multi, state.items

  if multi then
    local idxs = {}
    for i, selected in pairs(state.selections) do
      if selected and items[i] then
        idxs[#idxs + 1] = i
      end
    end
    table.sort(idxs)
    if #idxs == 0 then
      idxs = { line }
    end
    local chosen = {}
    for _, i in ipairs(idxs) do
      chosen[#chosen + 1] = items[i]
    end
    M.close()
    if cb and #chosen > 0 then
      cb(chosen, idxs)
    end
  else
    local item = items[line]
    M.close()
    if cb and item ~= nil then
      cb(item, line)
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

  local surf = surface.open({
    lines = opts.items,
    theme = opts.theme,
    title = opts.title,
    relative = opts.relative or "cursor",
    width = opts.width,
    height = opts.height or #opts.items,
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
  state.on_select = opts.on_select
  state.multi = opts.multi_select or opts.multi or false
  state.selections = {}

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

  if surf:is_valid() then
    api.nvim_win_set_cursor(surf.winid, { 1, 0 })
  end

  return surf
end

return M
