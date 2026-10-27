---@module 'lib.nvim.ui.kit.buttons'
--- Shared button-row helpers: the layout, the focus highlight and the mouse
--- hit-test that `kit.confirm`'s dialog and the button row under a
--- `kit.form`/`kit.input` field (`back = true`) have in common. They used to
--- live inside `kit.confirm`; a second row of `[ Label ]` boxes needing the
--- very same geometry is what made them a module, so that a click lands on
--- exactly the box that is drawn in both places and a change to the box shape
--- cannot be made in one and forgotten in the other.
---
--- Stateless on purpose. The callers are different shapes -- `confirm` is a
--- single-instance module with its own `state`, an input keeps its focus in a
--- closure -- so each keeps its own `labels`/`ranges`/`focus` and hands them
--- in. Nothing here owns a window, a buffer or a keymap.

local api = vim.api
local nul_safe = require("lib.lua.strings.core").nul_safe

local M = {}

--- Two spaces between neighbouring buttons.
local GAP = "  "

--- `[ Label ]` -- the drawn box. The ranges `layout` returns cover exactly this
--- string, so the click target is the visible box and nothing around it.
---@param label string
---@return string
function M.box(label)
  -- A label is one line of text: a newline in one is an error in `nvim_buf_set_lines`, and a NUL
  -- byte one in `strdisplaywidth()` (E976), which `row_width` and `layout` measure the row with.
  -- The box is only drawn and measured; what a caller gets back is its own label.
  return "[ " .. nul_safe((tostring(label):gsub("[\r\n]+", " "))) .. " ]"
end

--- Display width of the whole row, before any centering. What a caller sizes
--- its window with so the row is never wider than the float that holds it.
---@param labels string[]
---@return integer
function M.row_width(labels)
  local boxes = {}
  for i, l in ipairs(labels) do
    boxes[i] = M.box(l)
  end
  return vim.fn.strdisplaywidth(table.concat(boxes, GAP))
end

--- Build the centered button line and each button's byte-column range.
---
--- Ranges are 0-based byte columns (what an extmark takes) and `end_col` is
--- exclusive. The padding is spaces, so its byte length is also its width.
---@param labels string[]
---@param width integer  # window width the row is centered in
---@param row integer  # 0-based buffer row the buttons live on
---@return string line
---@return Lib.UI.Kit.ButtonRange[] ranges
function M.layout(labels, width, row)
  local boxes = {}
  for i, l in ipairs(labels) do
    boxes[i] = M.box(l)
  end
  local joined = table.concat(boxes, GAP)
  local pad = math.max(0, math.floor((width - vim.fn.strdisplaywidth(joined)) / 2))
  local line = string.rep(" ", pad) .. joined

  local ranges = {}
  local col = pad
  for i, box in ipairs(boxes) do
    ranges[i] = { row = row, start_col = col, end_col = col + #box }
    col = col + #box + #GAP
  end
  return line, ranges
end

--- A label cut so its box is at most `width` cells wide (`…` marks the cut). A label that already
--- fits is returned unchanged. What a caller answers with is still its own, uncut label.
---@param label string
---@param width integer
---@return string
local function fit_label(label, width)
  local overhead = vim.fn.strdisplaywidth(M.box(""))
  local room = math.max(1, width - overhead)
  local text = tostring(label):gsub("[\r\n]+", " ")
  if vim.fn.strdisplaywidth(nul_safe(text)) <= room then
    return label
  end
  local out, used = {}, 0
  for _, ch in ipairs(vim.fn.split(text, "\\zs")) do
    local w = vim.fn.strdisplaywidth(nul_safe(ch))
    if used + w > room - 1 then
      break
    end
    out[#out + 1] = ch
    used = used + w
  end
  return table.concat(out) .. "…"
end

--- Like `layout`, for a row that may not fit: the buttons are packed into as many centered rows
--- as it takes to keep each row within `width`, and a label wider than `width` is cut. With room
--- for all of them it is the same single row `layout` builds. Ranges carry the row of their
--- button, which is all `paint` and `hit` need.
---@param labels string[]
---@param width integer  # window width the rows are centered in
---@param first_row integer  # 0-based buffer row of the first button row
---@return string[] lines
---@return Lib.UI.Kit.ButtonRange[] ranges
function M.layout_rows(labels, width, first_row)
  local boxes = {}
  for i, l in ipairs(labels) do
    boxes[i] = M.box(fit_label(l, width))
  end

  -- Greedy packing: a box goes on the current row while the row stays within `width`.
  local rows, cur, cur_w = {}, {}, 0
  for i, box in ipairs(boxes) do
    local w = vim.fn.strdisplaywidth(box)
    local extra = #cur > 0 and #GAP or 0
    if #cur > 0 and cur_w + extra + w > width then
      rows[#rows + 1] = cur
      cur, cur_w, extra = {}, 0, 0
    end
    cur[#cur + 1] = i
    cur_w = cur_w + extra + w
  end
  if #cur > 0 then
    rows[#rows + 1] = cur
  end

  local lines, ranges = {}, {}
  for r, idxs in ipairs(rows) do
    local parts = {}
    for _, i in ipairs(idxs) do
      parts[#parts + 1] = boxes[i]
    end
    local joined = table.concat(parts, GAP)
    local pad = math.max(0, math.floor((width - vim.fn.strdisplaywidth(joined)) / 2))
    lines[r] = string.rep(" ", pad) .. joined
    local col = pad
    for _, i in ipairs(idxs) do
      ranges[i] = { row = first_row + r - 1, start_col = col, end_col = col + #boxes[i] }
      col = col + #boxes[i] + #GAP
    end
  end
  return lines, ranges
end

--- Repaint the focus highlight: clear `ns` in `buf`, then mark the focused
--- button with the theme's `KitSelection`. A nil or out-of-range `focus`
--- leaves the row unmarked (an input whose focus is in the field, not on the
--- buttons). A dead buffer is a no-op.
---@param buf integer|nil
---@param ns integer
---@param ranges Lib.UI.Kit.ButtonRange[]
---@param focus integer|nil  # 1-based
function M.paint(buf, ns, ranges, focus)
  if not buf or not api.nvim_buf_is_valid(buf) then
    return
  end
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local r = focus and ranges[focus]
  if r then
    pcall(api.nvim_buf_set_extmark, buf, ns, r.row, r.start_col, {
      end_col = r.end_col,
      hl_group = "KitSelection",
    })
  end
end

--- Which button (if any) the mouse is over, by hit-testing `getmousepos()`
--- against `ranges`. Reads live mouse state rather than relying on the click
--- having already moved the cursor first -- that ordering is not a contract
--- Neovim makes for a mapped `<LeftMouse>`, so hit-testing the click position
--- directly is the only version-independent way to know which button was hit.
---
--- The second return value tells a miss inside the window (blank space, the
--- text line) from a click somewhere else altogether: it is the
--- `getmousepos()` table when the click was in `winid`, nil otherwise.
---@param ranges Lib.UI.Kit.ButtonRange[]
---@param winid integer
---@return integer|nil index  # 1-based
---@return table|nil pos
function M.hit(ranges, winid)
  local pos = vim.fn.getmousepos()
  if pos.winid ~= winid then
    return nil, nil
  end
  local row, col = pos.line - 1, pos.column - 1 -- getmousepos() is 1-based
  for i, r in ipairs(ranges) do
    if r.row == row and col >= r.start_col and col < r.end_col then
      return i, pos
    end
  end
  return nil, pos
end

--- Move focus by `delta` buttons out of `n`, wrapping around.
---@param focus integer  # 1-based
---@param delta integer
---@param n integer
---@return integer
function M.wrap(focus, delta, n)
  if n <= 0 then
    return focus
  end
  return (focus - 1 + delta) % n + 1
end

return M
