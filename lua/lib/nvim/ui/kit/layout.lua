---@module 'lib.nvim.ui.kit.layout'
--- Layout / composition engine: turn a declarative region spec into concrete,
--- aligned `nvim_open_win` geometry for several coordinated floats, then mount
--- themed surfaces into those slots. This is the "three windows that line up
--- perfectly" primitive (see docs/ROADMAP/UI-KIT-CONCEPT.md §7).
---
--- `compute` is pure geometry math (no I/O), hence unit-testable; `mount` and
--- the templates build on it.

local surface = require("lib.nvim.ui.kit.surface")
local notify = require("lib.nvim.notify").create("[lib.nvim.ui.kit.layout]")

local M = {}

--- Border thickness assumed per slot when tiling (one cell all around).
local BORDER = 1

--- Resolve a size token against a total: a fraction (<=1) of `total`, a fixed
--- integer (>1), or nil.
---@param size number|nil
---@param total integer
---@return integer|nil
local function resolve_size(size, total)
  if size == nil then
    return nil
  end
  if size <= 1 then
    return math.floor(size * total)
  end
  return math.floor(size)
end

--- Distribute `avail` cells (minus gaps) across items whose `.size` is a
--- fraction, a fixed int, or nil (nil items share the remainder).
---@param items { size: number|nil }[]
---@param avail integer
---@param gap integer
---@return integer[]
local function distribute(items, avail, gap)
  local n = #items
  local inner = avail - gap * math.max(0, n - 1)
  local sizes = {}
  local used = 0
  local remainder = {}

  for i, it in ipairs(items) do
    local resolved = resolve_size(it.size, inner)
    if resolved == nil then
      remainder[#remainder + 1] = i
      sizes[i] = 0
    else
      sizes[i] = math.max(1, resolved)
      used = used + sizes[i]
    end
  end

  local left = inner - used
  if #remainder > 0 then
    local each = math.max(1, math.floor(left / #remainder))
    for _, i in ipairs(remainder) do
      sizes[i] = each
    end
    -- Any rounding leftover goes to the last remainder slot.
    sizes[remainder[#remainder]] = sizes[remainder[#remainder]] + (left - each * #remainder)
  elseif left ~= 0 and n > 0 then
    -- No remainder slot: absorb leftover into the last item.
    sizes[n] = math.max(1, sizes[n] + left)
  end

  return sizes
end

--- Convert an outer slot rectangle (including border) to content geometry that
--- `nvim_open_win` expects.
---@param x integer
---@param y integer
---@param w integer
---@param h integer
---@return table
local function to_content(x, y, w, h)
  return {
    relative = "editor",
    row = y + BORDER,
    col = x + BORDER,
    width = math.max(1, w - 2 * BORDER),
    height = math.max(1, h - 2 * BORDER),
  }
end

--- Compute concrete geometry for every named slot in a layout spec.
---@param spec table  # { width, height, relative?, row?, col?, gap?, rows = {...} }
---@return { slots: table<string, table>, outer: table }
function M.compute(spec)
  spec = spec or {}
  local cols = vim.o.columns
  local lines = vim.o.lines - (vim.o.cmdheight or 1)

  local ow = math.min(cols, resolve_size(spec.width, cols) or math.floor(cols * 0.8))
  local oh = math.min(lines, resolve_size(spec.height, lines) or math.floor(lines * 0.8))
  local row0 = spec.row or math.max(0, math.floor((lines - oh) / 2))
  local col0 = spec.col or math.max(0, math.floor((cols - ow) / 2))
  local gap = spec.gap or 0
  local rows = spec.rows or {}

  local row_items = {}
  for i, r in ipairs(rows) do
    row_items[i] = { size = r.height }
  end
  local row_heights = distribute(row_items, oh, gap)

  local slots = {}
  local y = row0
  for i, r in ipairs(rows) do
    local rh = row_heights[i]
    if r.cols then
      local col_items = {}
      for j, c in ipairs(r.cols) do
        col_items[j] = { size = c.width }
      end
      local col_widths = distribute(col_items, ow, gap)
      local x = col0
      for j, c in ipairs(r.cols) do
        local cw = col_widths[j]
        if c.name then
          slots[c.name] = to_content(x, y, cw, rh)
        end
        x = x + cw + gap
      end
    elseif r.name then
      slots[r.name] = to_content(col0, y, ow, rh)
    end
    y = y + rh + gap
  end

  return { slots = slots, outer = { row = row0, col = col0, width = ow, height = oh } }
end

--- Mount themed surfaces into a spec's slots. Closing any slot closes the group.
---@param spec table
---@param opts? { theme?: Lib.UI.Kit.ThemeArg, slot?: table<string, table>, enter?: string }
---@return { slots: table<string, Lib.UI.Kit.Surface>, close: fun() }
function M.mount(spec, opts)
  opts = opts or {}
  local geo = M.compute(spec)
  local surfaces = {}

  for name, g in pairs(geo.slots) do
    local slot_opts = vim.tbl_extend("force", {
      theme = opts.theme,
      relative = g.relative,
      row = g.row,
      col = g.col,
      width = g.width,
      height = g.height,
      enter = opts.enter == name,
    }, opts.slot and opts.slot[name] or {})
    surfaces[name] = surface.open(slot_opts)
  end

  local closing = false
  local function close_all()
    if closing then
      return
    end
    closing = true
    for _, s in pairs(surfaces) do
      if s then
        s:close()
      end
    end
  end

  for _, s in pairs(surfaces) do
    if s then
      s:on_close(close_all)
    end
  end

  return { slots = surfaces, close = close_all }
end

--- Named, ready-made layout templates. Each has a `.spec` you can mount as-is or
--- copy and modify.
M.templates = {
  picker = {
    spec = {
      width = 0.8,
      height = 0.8,
      gap = 0,
      rows = {
        { name = "prompt", height = 3 },
        {
          cols = {
            { name = "results", width = 0.4 },
            { name = "preview", width = 0.6 },
          },
        },
      },
    },
  },
}

--- Mount a template by name. `opts.spec` (a partial table) is deep-merged over
--- the template's spec first, so callers can tweak sizes.
---@param name string
---@param opts? table
---@return { slots: table<string, Lib.UI.Kit.Surface>, close: fun() }|nil
function M.template(name, opts)
  opts = opts or {}
  local t = M.templates[name]
  if not t then
    notify.error(("unknown layout template %q"):format(tostring(name)))
    return nil
  end
  local spec = vim.deepcopy(t.spec)
  if type(opts.spec) == "table" then
    spec = vim.tbl_deep_extend("force", spec, opts.spec)
  end
  return M.mount(spec, opts)
end

return M
