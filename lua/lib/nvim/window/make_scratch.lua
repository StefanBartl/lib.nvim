---@module 'lib.nvim.window.make_scratch'
---Create a scratch buffer inside a floating window in one call.
---
---Returns `winid, bufnr` (or `nil` on failure). The buffer is an unlisted
---`nofile` scratch buffer wiped on hide; the window is a centered float with
---sensible overlay defaults (no numbers, no signcolumn, no wrap) that callers
---can override. Optionally attaches `nice_quit` so the overlay closes with
---`q` / `<Esc>` straight away.

require("lib.nvim.window.@types")

local api = vim.api
local notify = require("lib.nvim.notify").create("[lib.nvim.window.make_scratch]")
local nice_quit = require("lib.nvim.window.nice_quit")

---Window-local options applied to every scratch float unless overridden via `opts.wo`.
local DEFAULT_WO = {
  number = false,
  relativenumber = false,
  signcolumn = "no",
  wrap = false,
  cursorline = false,
}

---Widest display column count across `lines` (multibyte-aware).
---@param lines string[]
---@return integer
local function content_width(lines)
  local max = 0
  for _, line in ipairs(lines) do
    local w = vim.fn.strdisplaywidth(line)
    if w > max then
      max = w
    end
  end
  return max
end

---Clamp `value` into the inclusive `[lo, hi]` range.
---@param value integer
---@param lo integer
---@param hi integer
---@return integer
local function clamp(value, lo, hi)
  return math.max(lo, math.min(value, hi))
end

---Resolve width/height from opts and content, clamped to the editor size.
---@param lines string[]
---@param opts Lib.Window.MakeScratchOpts
---@return integer width
---@return integer height
local function resolve_dimensions(lines, opts)
  local max_w = math.max(1, vim.o.columns - 4)
  local max_h = math.max(1, vim.o.lines - 4)

  -- +2 leaves room for a border; fall back to a comfortable default when empty.
  local want_w = opts.width or (content_width(lines) + 2)
  if want_w <= 2 then
    want_w = math.min(60, max_w)
  end

  local want_h = opts.height or #lines
  if want_h < 1 then
    want_h = 1
  end

  return clamp(want_w, 1, max_w), clamp(want_h, 1, max_h)
end

---Create the scratch buffer and fill it with `lines`.
---@param lines string[]
---@param opts Lib.Window.MakeScratchOpts
---@return integer|nil bufnr
local function create_buffer(lines, opts)
  local ok, bufnr = pcall(api.nvim_create_buf, false, true)
  if not ok or not bufnr or bufnr == 0 then
    notify.error("make_scratch: failed to create buffer")
    return nil
  end

  api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })
  api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
  api.nvim_set_option_value("swapfile", false, { buf = bufnr })

  if #lines > 0 then
    api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end

  if opts.filetype ~= nil then
    api.nvim_set_option_value("filetype", opts.filetype, { buf = bufnr })
  end

  for name, value in pairs(opts.bo or {}) do
    pcall(api.nvim_set_option_value, name, value, { buf = bufnr })
  end

  -- Lock the buffer last (default), after content and caller overrides are in.
  if opts.modifiable ~= true then
    api.nvim_set_option_value("modifiable", false, { buf = bufnr })
    api.nvim_set_option_value("modified", false, { buf = bufnr })
  end

  return bufnr
end

---Build the floating-window config, centering on the editor when no position is given.
---@param width integer
---@param height integer
---@param opts Lib.Window.MakeScratchOpts
---@return table
local function build_win_config(width, height, opts)
  local relative = opts.relative or "editor"

  local row = opts.row
  local col = opts.col
  if relative == "editor" and row == nil and col == nil then
    row = math.max(0, math.floor((vim.o.lines - height) / 2 - 1))
    col = math.max(0, math.floor((vim.o.columns - width) / 2))
  end

  ---@type table
  local cfg = {
    relative = relative,
    width = width,
    height = height,
    row = row or 1,
    col = col or 0,
    border = opts.border or "rounded",
    style = "minimal",
    focusable = opts.focusable ~= false,
  }
  if opts.title ~= nil then
    cfg.title = opts.title
    if opts.title_pos ~= nil then
      cfg.title_pos = opts.title_pos
    end
  end
  if opts.zindex ~= nil then
    cfg.zindex = opts.zindex
  end
  return cfg
end

---Create a scratch buffer in a floating window.
---@param opts? Lib.Window.MakeScratchOpts
---@return integer|nil winid
---@return integer|nil bufnr
local function make_scratch(opts)
  opts = opts or {}
  local lines = opts.lines or {}

  local bufnr = create_buffer(lines, opts)
  if not bufnr then
    return nil, nil
  end

  local width, height = resolve_dimensions(lines, opts)
  local win_config = build_win_config(width, height, opts)

  local enter = opts.enter ~= false
  local ok, winid = pcall(api.nvim_open_win, bufnr, enter, win_config)
  if not ok or not winid or winid == 0 then
    notify.error("make_scratch: failed to create window")
    pcall(api.nvim_buf_delete, bufnr, { force = true })
    return nil, nil
  end

  -- Apply overlay window-local options, then caller overrides.
  for name, value in pairs(DEFAULT_WO) do
    pcall(api.nvim_set_option_value, name, value, { win = winid })
  end
  for name, value in pairs(opts.wo or {}) do
    pcall(api.nvim_set_option_value, name, value, { win = winid })
  end

  -- Optional: wire up q / <Esc> to close, reusing the dedicated helper.
  if opts.nice_quit then
    ---@type Lib.Window.NiceQuitOpts|nil
    local nq_opts
    if type(opts.nice_quit) == "table" then
      nq_opts = opts.nice_quit --[[@as Lib.Window.NiceQuitOpts]]
    end
    nice_quit(winid, nq_opts)
  end

  return winid, bufnr
end

return make_scratch
