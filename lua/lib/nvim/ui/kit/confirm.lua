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
local nul_safe = require("lib.lua.strings.core").nul_safe

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

--- How often a waiting `ask` looks again, and how long it waits at most.
M.ASK_POLL_MS = 300
M.ASK_MAX_WAIT_MS = 10 * 60 * 1000

--- The questions `ask` is holding back, oldest first (a ticket each).
---@type table[]
local waiting = {}

---@param ticket table
local function leave_queue(ticket)
  for i, t in ipairs(waiting) do
    if t == ticket then
      table.remove(waiting, i)
      return
    end
  end
end

--- Yes/no question that waits its turn and always answers, "no" included.
---
--- `open` is single-instance: opening a dialog closes the open one WITHOUT
--- answering it, so a question raised while another is showing (a stream
--- that ends minutes after the command was typed) would vanish unanswered.
--- `ask` instead polls until no dialog is open, then shows its own. Anything
--- that is not an explicit yes -- a dialog that stays open for `max_wait_ms`
--- -- calls `on_answer(false)`, so callers treat an unanswered question as
--- "no" without a second code path. When the float cannot be opened at all
--- it falls back to `vim.ui.select` (Yes/No).
---
--- Several waiting questions are shown in the order they were asked, whichever
--- of their polls happens to tick first.
---
--- `on_answer` fires at most once, and never when `abandoned()` is true by
--- the time the question's turn comes.
---@param opts { question: string, on_answer: fun(yes: boolean), abandoned?: (fun(): boolean), theme?: any, title?: string, max_wait_ms?: integer }
---@return nil
function M.ask(opts)
  opts = opts or {}
  local waited = 0
  local max_wait = opts.max_wait_ms or M.ASK_MAX_WAIT_MS
  local answered = false
  local ticket = {}
  waiting[#waiting + 1] = ticket
  local function answer(yes)
    if answered then
      return
    end
    answered = true
    if opts.on_answer then
      opts.on_answer(yes == true)
    end
  end

  local attempt
  local function step()
    if opts.abandoned and opts.abandoned() then
      leave_queue(ticket)
      return
    end
    if waiting[1] ~= ticket or M.is_open() then
      if waited >= max_wait then
        leave_queue(ticket)
        answer(false)
        return
      end
      waited = waited + M.ASK_POLL_MS
      vim.defer_fn(attempt, M.ASK_POLL_MS)
      return
    end
    leave_queue(ticket)
    -- `open` answers "no" synchronously and returns nil when the float cannot be
    -- created: a failure to show the question, not an answer, so it is not
    -- forwarded. A dialog that did open and answers at once (a stub, another
    -- implementation) is a real answer and counts.
    local opening = true
    local sync_answer
    local shown = M.open({
      question = opts.question,
      theme = opts.theme,
      title = opts.title,
      on_answer = function(yes)
        if opening then
          sync_answer = yes
        else
          answer(yes)
        end
      end,
    })
    opening = false
    if shown then
      if sync_answer ~= nil then
        answer(sync_answer)
      end
    else
      vim.ui.select({ "Yes", "No" }, { prompt = tostring(opts.question or "") }, function(choice)
        answer(choice == "Yes")
      end)
    end
  end

  -- A step that raises (a throwing `abandoned`, a failing `open`) must not leave its
  -- place in the queue, or every question behind it would wait for ever.
  attempt = function()
    local ok, err = pcall(step)
    if not ok then
      leave_queue(ticket)
      error(err, 0)
    end
  end
  attempt()
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
    -- A NUL byte in the question (a case title, say) would raise E976 out of the
    -- `strdisplaywidth()` that sizes and centers it: it is shown as the SOH that measures alike.
    qlines[#qlines + 1] = nul_safe(ql)
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
