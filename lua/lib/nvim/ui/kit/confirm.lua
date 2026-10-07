---@module 'lib.nvim.ui.kit.confirm'
--- Button-confirm component: a question with a row of horizontal buttons
--- reachable with h/l (or arrows / <Tab>), <CR> confirms the focused button,
--- <Esc>/q cancels. A left click on a button focuses *and* confirms it in
--- one action, like a real button (not a two-step "click to focus, Enter to
--- confirm" — `state.ranges`, already tracked for the focus-highlight
--- extmark, is exactly the per-button screen geometry a click needs to hit-
--- test against, so this is additive over existing state, not new state).
--- The focused button is highlighted with the theme's `KitSelection` group.
--- This is the Phase-4 "cherry on top" of the UI-kit design
--- §9; sketch: assets/ui-kit/confirm-buttons.svg.
---
--- Answer contract (matches the list-based confirm in prompt.lua):
---   - default { "Yes", "No" }  -> on_answer(boolean)  (Yes == true)
---   - custom `choices`         -> on_answer(choice_string)
---   - cancel (<Esc>/q)         -> on_answer(false) for the default case,
---                                 on_answer(nil) for a custom choice list.

local surface = require("lib.nvim.ui.kit.surface")
local buttons = require("lib.nvim.ui.kit.buttons")
local map = require("lib.nvim.bindings.keymap")

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

---@internal
---@param s string
---@param width integer
---@return string
local function center(s, width)
  local pad = math.max(0, math.floor((width - vim.fn.strdisplaywidth(s)) / 2))
  return string.rep(" ", pad) .. s
end

---@internal
--- Repaint the focus highlight on the current button.
local function render_focus()
  buttons.paint(state.surf and state.surf.bufnr, state.ns, state.ranges, state.focus)
end

--- Whether a confirm dialog is currently open.
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

--- 1-based index of the currently focused button.
---@return integer
function M.current_focus()
  return state.focus
end

---@internal
--- Which button (if any) the mouse is currently over -- the hit-test itself
--- (live `getmousepos()` against `state.ranges`) is `lib.nvim.ui.kit.buttons.hit`.
---@return integer|nil
local function button_at_mousepos()
  if not M.is_open() then
    return nil
  end
  return (buttons.hit(state.ranges, state.surf.winid))
end

--- Focus and confirm whichever button is under the mouse, if any. A click
--- that misses every button (blank space in the dialog) is a no-op, not a
--- cancel — matches clicking empty space anywhere else in the kit, which
--- never dismisses the surface either.
function M.click()
  local i = button_at_mousepos()
  if not i then
    return
  end
  state.focus = i
  render_focus()
  M.confirm()
end

--- Move focus by `delta` buttons, wrapping around.
---@param delta integer
function M.move(delta)
  if not M.is_open() then
    return
  end
  state.focus = buttons.wrap(state.focus, delta, #state.labels)
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
  local btn_w = buttons.row_width(labels)
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
  local button_line, ranges = buttons.layout(labels, width, button_row)
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
    -- `surface.open` failed to open the float -- a genuine break, not a
    -- user-driven cancel. Without this, on_answer never fires (despite the
    -- module's own "Answer contract" implying it always does) and a
    -- kit.sync caller blocked on it stalls silently. Same "no answer" value
    -- as M.cancel() uses.
    if opts.on_answer then
      if custom then
        opts.on_answer(nil)
      else
        opts.on_answer(false)
      end
    end
    return nil
  end

  state.surf = surf
  state.labels = labels
  state.ranges = ranges
  state.focus = 1
  state.custom = custom
  state.on_answer = opts.on_answer
  render_focus()

  -- Throwaway buffer-local keys: not recorded (see lib.nvim.ui.kit.chooser's `mo`).
  local mo = { buffer = surf.bufnr, nowait = true, record = false }
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
  map("n", "<LeftMouse>", M.click, mo)

  return surf
end

return M
