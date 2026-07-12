---@module 'lib.nvim.ui.kit.confirm'
--- Button-confirm component: a question with a row of horizontal buttons
--- reachable with h/l (or arrows / <Tab>), <CR> confirms the focused button,
--- <Esc>/q cancels. The focused button is highlighted with the theme's
--- `KitSelection` group. This is the Phase-4 "cherry on top" from
--- docs/ROADMAP/UI-KIT-CONCEPT.md §9; sketch: assets/ui-kit/confirm-buttons.svg.
---
--- Answer contract (matches the list-based confirm in prompt.lua):
---   - default { "Yes", "No" }  -> on_answer(boolean)  (Yes == true)
---   - custom `choices`         -> on_answer(choice_string)
---   - cancel (<Esc>/q)         -> on_answer(false) for the default case,
---                                 on_answer(nil) for a custom choice list.

local surface = require("lib.nvim.ui.kit.surface")
local map = require("lib.nvim.map")

local api = vim.api

local M = {}

--- Single active confirm dialog (mirrors the chooser's single-instance model).
local state = {
  surf = nil,
  labels = {},
  focus = 1,
  ranges = {}, -- per-button { row, start_col, end_col } (0-based, byte cols)
  custom = false,
  on_answer = nil,
  ns = api.nvim_create_namespace("lib_kit_confirm"),
}

---@param s string
---@param width integer
---@return string
local function center(s, width)
  local pad = math.max(0, math.floor((width - vim.fn.strdisplaywidth(s)) / 2))
  return string.rep(" ", pad) .. s
end

--- Build the centered button line and each button's byte-column range.
---@param labels string[]
---@param width integer
---@param row integer  # 0-based buffer row the buttons live on
---@return string line, table ranges
local function build_button_line(labels, width, row)
  local btns = {}
  for i, l in ipairs(labels) do
    btns[i] = "[ " .. l .. " ]"
  end
  local joined = table.concat(btns, "  ")
  local pad = math.max(0, math.floor((width - vim.fn.strdisplaywidth(joined)) / 2))
  local line = string.rep(" ", pad) .. joined

  local ranges = {}
  local col = pad
  for i, btn in ipairs(btns) do
    ranges[i] = { row = row, start_col = col, end_col = col + #btn }
    col = col + #btn + 2 -- account for the two-space separator
  end
  return line, ranges
end

--- Repaint the focus highlight on the current button.
local function render_focus()
  local buf = state.surf and state.surf.bufnr
  if not buf or not api.nvim_buf_is_valid(buf) then
    return
  end
  api.nvim_buf_clear_namespace(buf, state.ns, 0, -1)
  local r = state.ranges[state.focus]
  if r then
    pcall(api.nvim_buf_set_extmark, buf, state.ns, r.row, r.start_col, {
      end_col = r.end_col,
      hl_group = "KitSelection",
    })
  end
end

---@return boolean
function M.is_open()
  return state.surf ~= nil and state.surf:is_valid()
end

--- Close and reset (idempotent).
function M.close()
  if state.surf then
    state.surf:close()
  end
  state.surf = nil
  state.labels = {}
  state.ranges = {}
  state.focus = 1
  state.custom = false
  state.on_answer = nil
end

---@return integer
function M.current_focus()
  return state.focus
end

--- Move focus by `delta` buttons, wrapping around.
---@param delta integer
function M.move(delta)
  if not M.is_open() then
    return
  end
  local n = #state.labels
  if n == 0 then
    return
  end
  state.focus = (state.focus - 1 + delta) % n + 1
  render_focus()
end

--- Confirm the focused button, fire on_answer, then close.
function M.confirm()
  if not M.is_open() then
    return
  end
  local cb, custom, labels, focus = state.on_answer, state.custom, state.labels, state.focus
  M.close()
  if cb then
    if custom then
      cb(labels[focus])
    else
      cb(focus == 1)
    end
  end
end

--- Cancel the dialog (Esc/q), fire on_answer with the cancelled value, close.
function M.cancel()
  if not M.is_open() then
    return
  end
  local cb, custom = state.on_answer, state.custom
  M.close()
  if cb then
    if custom then
      cb(nil)
    else
      cb(false)
    end
  end
end

--- Open a button-confirm dialog.
---@param opts table  # { question, choices?, theme?, on_answer }
---@return Lib.UI.Kit.Surface|nil
function M.open(opts)
  opts = opts or {}
  M.close()

  local custom = type(opts.choices) == "table" and #opts.choices > 0
  local labels = custom and opts.choices or { "Yes", "No" }

  local qlines = {}
  for _, ql in ipairs(vim.split(tostring(opts.question or ""), "\n", { plain = true })) do
    qlines[#qlines + 1] = ql
  end

  -- Width: fit the wider of the question and the button row, plus margin.
  local btns_join = {}
  for i, l in ipairs(labels) do
    btns_join[i] = "[ " .. l .. " ]"
  end
  local btn_w = vim.fn.strdisplaywidth(table.concat(btns_join, "  "))
  local q_w = 0
  for _, ql in ipairs(qlines) do
    q_w = math.max(q_w, vim.fn.strdisplaywidth(ql))
  end
  local width = math.max(btn_w, q_w) + 4

  -- Compose lines: question (centered), blank, buttons.
  local lines = {}
  for _, ql in ipairs(qlines) do
    lines[#lines + 1] = center(ql, width)
  end
  lines[#lines + 1] = ""
  local button_row = #lines -- 0-based row of the button line (current #lines before append)
  local button_line, ranges = build_button_line(labels, width, button_row)
  lines[#lines + 1] = button_line

  local surf = surface.open({
    lines = lines,
    theme = opts.theme,
    title = opts.title,
    width = width,
    height = #lines,
    relative = opts.relative or "editor",
    enter = true,
    filetype = "lib-kit-confirm",
  })
  if not surf then
    return nil
  end

  state.surf = surf
  state.labels = labels
  state.ranges = ranges
  state.focus = 1
  state.custom = custom
  state.on_answer = opts.on_answer
  render_focus()

  local mo = { buffer = surf.bufnr, nowait = true }
  for _, key in ipairs({ "l", "<Right>", "<Tab>" }) do
    map("n", key, function()
      M.move(1)
    end, mo)
  end
  for _, key in ipairs({ "h", "<Left>", "<S-Tab>" }) do
    map("n", key, function()
      M.move(-1)
    end, mo)
  end
  map("n", "<CR>", M.confirm, mo)
  map("n", "<Esc>", M.cancel, mo)
  map("n", "q", M.cancel, mo)

  return surf
end

return M
