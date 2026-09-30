---@module 'lib.nvim.ui.kit.toast'
--- Toast component: an ephemeral, non-focus-stealing message in the top-right
--- corner that auto-dismisses. Toasts stack downward.
---
--- Width: a toast is as wide as its text plus padding, but never narrower than
--- `min_width` (default 40 columns, so a ten-character message still gets a
--- comfortable chip) and never wider than `width` (default 40% of the editor).
--- Both take a column count or a `"NN%"` string of the editor width, and are
--- re-evaluated on every reflow, so a resize is followed.
---
--- This submodule owns a small internal registry of the currently visible
--- toasts (needed to stack them). That state is confined here and exposed only
--- through `active()` — no shared global window state.

local surface = require("lib.nvim.ui.kit.surface")
local autocmd = require("lib.nvim.bindings.autocmd")

local api = vim.api

local M = {}

local DEFAULT_TIMEOUT = 3000
local MARGIN = 2 -- columns from the right edge / rows from the top
local MIN_CONTENT = 10 -- never narrower than this, whatever the user asks for

---@class Lib.UI.Kit.ToastConfig
---@field width? integer|string      # Widest a toast may get: columns or "NN%" of the editor width (default "40%")
---@field min_width? integer|string  # Narrowest a toast may get: columns or "NN%" (default 40)
---@field padding? integer           # Blank columns left and right of the text inside the chip (default 1)

---@type { width: integer|string, min_width: integer|string, padding: integer }
local config = { width = "40%", min_width = 40, padding = 1 }

--- Live toasts, oldest first. Each: { surf = Surface, height = integer, bordered = boolean, content = integer }.
local stack = {}

---@param v any
---@return boolean
local function valid_size(v)
  if type(v) == "number" then
    return v > 0
  end
  return type(v) == "string" and v:match("^%s*%d+%.?%d*%s*%%?%s*$") ~= nil
end

--- Columns for a size spec (`40` or `"40%"`) on an editor `columns` wide.
---@param v integer|string
---@param columns integer
---@param fallback integer
---@return integer
local function resolve_cols(v, columns, fallback)
  if type(v) == "number" then
    return math.floor(v)
  end
  if type(v) == "string" then
    local pct = v:match("^%s*(%d+%.?%d*)%s*%%%s*$")
    if pct then
      return math.floor(columns * tonumber(pct) / 100)
    end
    local n = tonumber(v)
    if n then
      return math.floor(n)
    end
  end
  return fallback
end

--- Current (min, max) content width in columns. `max` leaves room for the
--- margin and the border; `min` is pulled down to `max` on a narrow editor.
---@return integer min_w
---@return integer max_w
local function limits()
  local columns = vim.o.columns
  local hard = math.max(MIN_CONTENT, columns - 2 * MARGIN - 2)
  local max_w = resolve_cols(config.width, columns, math.floor(columns * 0.4))
  max_w = math.min(math.max(max_w, MIN_CONTENT), hard)
  local min_w = resolve_cols(config.min_width, columns, 40)
  min_w = math.min(math.max(min_w, MIN_CONTENT), max_w)
  return min_w, max_w
end

--- Change the width limits / padding. Unset fields keep their value; an
--- invalid value is ignored rather than raised (a notification path must not
--- throw).
---@param opts? Lib.UI.Kit.ToastConfig
function M.setup(opts)
  opts = opts or {}
  if valid_size(opts.width) then
    config.width = opts.width
  end
  if valid_size(opts.min_width) then
    config.min_width = opts.min_width
  end
  if type(opts.padding) == "number" and opts.padding >= 0 then
    config.padding = math.min(math.floor(opts.padding), 4)
  end
end

--- Widest a toast's content (inside border and padding) can be right now --
--- what a caller wrapping its own text should wrap to.
---@return integer
function M.inner_width()
  local _, max_w = limits()
  return math.max(1, max_w - 2 * config.padding)
end

--- Hard-wrap `lines` to `width` display columns (no word logic: a toast is a
--- short message, and a stable cut beats a clever one).
---@param lines string[]
---@param width integer
---@return string[]
local function wrap_lines(lines, width)
  local out = {}
  for _, line in ipairs(lines) do
    local rest = line
    while vim.fn.strdisplaywidth(rest) > width do
      local lo, hi = 1, vim.fn.strchars(rest)
      while lo < hi do
        local mid = math.ceil((lo + hi) / 2)
        if vim.fn.strdisplaywidth(vim.fn.strcharpart(rest, 0, mid)) <= width then
          lo = mid
        else
          hi = mid - 1
        end
      end
      out[#out + 1] = vim.fn.strcharpart(rest, 0, lo)
      rest = vim.fn.strcharpart(rest, lo)
    end
    out[#out + 1] = rest
  end
  return out
end

--- Width of a toast whose text is `content` columns wide, inside the current limits.
---@param content integer
---@return integer
local function fit_width(content)
  local min_w, max_w = limits()
  return math.min(math.max(content + 2 * config.padding, min_w), max_w)
end

---@internal
--- Drop dead toasts and reflow the survivors from the top-right corner down.
---
--- `row` (per `nvim_win_set_config`) is a bordered float's *content* row --
--- the border itself is drawn one row above/below that, outside `height` --
--- so a bordered toast's true on-screen footprint is `height + 2` rows, not
--- `height`. Advancing `row` by only `t.height + 1` (as if every toast were
--- borderless) used to leave the two border rows unaccounted for, so the
--- next toast's top border landed exactly on the previous one's bottom
--- border -- overwriting it instead of leaving a gap below it.
local function reflow()
  local live = {}
  for _, t in ipairs(stack) do
    if t.surf:is_valid() then
      live[#live + 1] = t
    end
  end
  stack = live

  local row = MARGIN - 1
  for _, t in ipairs(stack) do
    local width = fit_width(t.content)
    pcall(api.nvim_win_set_config, t.surf.winid, {
      relative = "editor",
      row = row,
      col = math.max(0, vim.o.columns - width - MARGIN),
      width = width,
      height = t.height,
    })
    local box_h = t.bordered and (t.height + 2) or t.height
    row = row + box_h + 1
  end
end

--- Show a toast.
---@param opts table  # { message, title?, theme?, timeout? }
---@return Lib.UI.Kit.Surface|nil
function M.open(opts)
  opts = opts or {}
  local message = opts.message or ""
  local lines = type(message) == "table" and message
    or vim.split(tostring(message), "\n", { plain = true })

  -- Wrap to what fits, then pad both sides, then measure: the chip is as
  -- wide as its widest line (see `fit_width`).
  lines = wrap_lines(lines, M.inner_width())
  local content = 0
  for _, line in ipairs(lines) do
    content = math.max(content, vim.fn.strdisplaywidth(line))
  end
  local pad = string.rep(" ", config.padding)
  local padded = {}
  for i, line in ipairs(lines) do
    padded[i] = pad .. line .. pad
  end

  -- The theme's own `zindex.toast` (70), not the `popup` default (50) that
  -- `surface.open` falls back to: at 50 a toast sat UNDER a snacks picker
  -- (layout 52, windows 54) and was simply never seen while one was open.
  local ok_theme, resolved = pcall(function()
    return require("lib.nvim.ui.kit.theme").resolve(opts.theme)
  end)
  local zindex = ok_theme and resolved.zindex and resolved.zindex.toast or nil

  local surf = surface.open({
    lines = padded,
    theme = opts.theme,
    zindex = zindex,
    title = opts.title,
    width = fit_width(content),
    height = #padded,
    relative = "editor",
    row = 0,
    col = 0,
    enter = false, -- never steal focus
    focusable = false,
  })
  if not surf then
    return nil
  end

  local entry =
    { surf = surf, height = #padded, bordered = surf.border ~= "none", content = content }
  stack[#stack + 1] = entry
  reflow()

  surf:on_close(reflow)

  local timeout = tonumber(opts.timeout) or DEFAULT_TIMEOUT
  if timeout > 0 then
    vim.defer_fn(function()
      surf:close()
    end, timeout)
  end

  return surf
end

-- Same bug class as PERF-92 (`ui.screenkey`, `lib.nvim.ui.kit.{compare,picker,
-- chooser}`): `reflow()` only ran when a toast opened or closed, so a
-- `VimResized` while one was up left it pinned to the corner computed at the
-- editor's PREVIOUS size until the next open/close reflowed it -- and
-- `M.open`'s `timeout = 0` disables the auto-dismiss entirely, so that
-- window is not bounded the way a default 3s toast's is. Registered once at
-- module load, not per-toast: `reflow()` is already idempotent over an empty
-- `stack`, so there is nothing to enable/disable.
autocmd.create("VimResized", reflow, {
  group = autocmd.group("lib_kit_toast_resize", true),
  desc = "lib.nvim.ui.kit.toast: keep the stack pinned to its corner",
})

--- Number of live toasts (also prunes dead ones).
---@return integer
function M.active()
  reflow()
  return #stack
end

--- Close every visible toast.
function M.clear()
  for _, t in ipairs(stack) do
    t.surf:close()
  end
  reflow()
end

return M
