---@module 'lib.nvim.ui.kit.sidebar'
--- A sidebar is one themed split -- a panel on the left, the right or the bottom of the
--- tabpage, like a file tree or a test explorer -- plus the lifecycle handle of
--- `lib.nvim.ui.kit.surface` (it inherits `set_lines`, `append_lines`, `on_close`, ...).
--- `kit.surface` stays the float primitive; this is its split counterpart.
---
--- * Fixed size: `winfixwidth` (left/right) or `winfixheight` (bottom), so `<C-w>=` and new
---   splits leave the panel alone. `winfixbuf`, no numbers/signs/folds, `cursorline` on.
--- * Theme: `winhighlight` maps `Normal`, `NormalNC`, `EndOfBuffer`, `SignColumn` to the kit's
---   `normal` token, `WinSeparator` to `border`, `WinBar` to `title` and `CursorLine` to
---   `KitSelection`, from the same `theme` argument every kit component takes.
--- * Exclusive slots (UI-54): a sidebar opened at a position where another one is visible in
---   the same tabpage hides that one and remembers it; when the newer one is closed or hidden,
---   the displaced one comes back, exactly once, two `vim.schedule` ticks later (a window
---   created on `WinEnter` can still report the previous window's buffer for a moment).
---   `exclusive = false` lets a sidebar share its slot instead.
--- * Handles live in `lib.nvim.ui.kit.sidebar_state` (UI-51); `close_all()` is the one cleanup
---   (UI-52); a window is found again through its buffer variable `ui_kit_sidebar` (UI-31) --
---   the buffer survives `hide()`, a window-local variable would not.

local surface = require("lib.nvim.ui.kit.surface")
local theme = require("lib.nvim.ui.kit.theme")
local state = require("lib.nvim.ui.kit.sidebar_state")
local winhighlight = require("lib.nvim.ui.winhighlight")

local api = vim.api

local M = {}

--- The buffer variable that names the sidebar a buffer belongs to (`vim.b[buf].ui_kit_sidebar`).
---@type string
M.BUF_VAR = "ui_kit_sidebar"

--- `nvim_open_win`'s `split` value per position.
local SPLIT = { left = "left", right = "right", bottom = "below" }

--- Width (left/right) or height (bottom) when `size` is not given.
local DEFAULT_SIZE = { left = 30, right = 30, bottom = 10 }

--- Set while `close_all` runs: nothing is restored on the way out.
local closing_all = false

--- Counter for sidebars opened without a name.
local unnamed = 0

-- The public fields are declared in `@types`; these are the internal ones (the surface's own
-- `_closed`/`_on_close`/`_augroup` included: a sidebar uses them the same way).
---@class Lib.UI.Kit.Sidebar
---@field package _closed boolean
---@field package _on_close function[]
---@field package _augroup integer|nil
---@field package _tab integer
---@field package _resolved Lib.UI.Kit.Theme
---@field package _wo table<string, any>
local Sidebar = {}
Sidebar.__index = Sidebar
setmetatable(Sidebar, { __index = surface.Handle })

--- Run `fn` two main-loop ticks from now (UI-54).
---@param fn fun()
local function defer_twice(fn)
  vim.schedule(function()
    vim.schedule(fn)
  end)
end

--- The window size for `position`: an integer is taken as is, a fraction (0 < size < 1) is a
--- share of the editor's width or height. Clamped so the rest of the tabpage keeps a line.
---@param position string
---@param size number|nil
---@return integer
local function resolve_size(position, size)
  local total = position == "bottom" and (vim.o.lines - vim.o.cmdheight - 1) or vim.o.columns
  size = size or DEFAULT_SIZE[position]
  if size > 0 and size < 1 then
    size = math.floor(total * size + 0.5)
  end
  return math.max(1, math.min(math.floor(size), total - 1))
end

--- `%` is a statusline item in 'winbar'; a title shows it literally.
---@param title string
---@return string
local function winbar_text(title)
  return " " .. title:gsub("%%", "%%%%")
end

--- Window options, theme and title onto the sidebar's (new) window.
---@param self Lib.UI.Kit.Sidebar
local function decorate(self)
  local win = self.winid
  local fixed = self.position == "bottom" and "winfixheight" or "winfixwidth"
  local wo = vim.tbl_extend("force", {
    winfixbuf = true,
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    -- A split copies the fold settings too: `foldmethod=indent` would close a tree's children.
    foldenable = false,
    foldmethod = "manual",
    statuscolumn = "",
    spell = false,
    list = false,
    wrap = false,
    cursorline = true,
    winbar = self.title and winbar_text(self.title) or "",
    [fixed] = true,
  }, self._wo)

  -- A split copies the options of the window it was made from: set every one of them
  -- (`winhighlight` from scratch, not merged into a code window's own mappings).
  theme.materialize(self._resolved)
  local names = theme.window_groups(self._resolved)
  winhighlight.apply(
    win,
    winhighlight.merge(nil, {
      Normal = names.normal,
      NormalNC = names.normal,
      EndOfBuffer = names.normal,
      SignColumn = names.normal,
      WinSeparator = names.border,
      WinBar = names.title,
      WinBarNC = names.title,
      CursorLine = "KitSelection",
    })
  )
  for name, value in pairs(wo) do
    pcall(api.nvim_set_option_value, name, value, { scope = "local", win = win })
  end
end

--- Delete `buf` now, or (while a closing window still shows it) on the next tick.
---@param buf integer
local function drop_buffer(buf)
  if not api.nvim_buf_is_valid(buf) then
    return
  end
  -- A last window that cannot close keeps the buffer; `winfixbuf` would refuse the
  -- replacement buffer the delete puts there.
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    pcall(api.nvim_set_option_value, "winfixbuf", false, { win = win })
  end
  if not pcall(api.nvim_buf_delete, buf, { force = true }) then
    vim.schedule(function()
      if api.nvim_buf_is_valid(buf) then
        pcall(api.nvim_buf_delete, buf, { force = true })
      end
    end)
  end
end

--- Is `win` the only non-floating window of its tabpage? Closing it would close the tabpage
--- (or fail with E444 in the last one).
---@param win integer
---@return boolean
local function is_last_window(win)
  local splits = 0
  for _, w in ipairs(api.nvim_tabpage_list_wins(api.nvim_win_get_tabpage(win))) do
    if api.nvim_win_get_config(w).relative == "" then
      splits = splits + 1
    end
  end
  return splits <= 1
end

---@param self Lib.UI.Kit.Sidebar
local function unwatch(self)
  if self._augroup then
    pcall(api.nvim_del_augroup_by_id, self._augroup)
    self._augroup = nil
  end
end

local finish

--- Bring `target` back after the sidebar that displaced it went away (once: the caller took
--- it out of the state). A slot taken again in the meantime keeps its occupant; `target`
--- then waits behind it.
---@param target Lib.UI.Kit.Sidebar
local function restore(target)
  defer_twice(function()
    if closing_all or target._closed or target:is_visible() then
      return
    end
    if not api.nvim_tabpage_is_valid(target._tab) then
      return
    end
    local occupant = state.visible_at(target._tab, target.position, target)
    if occupant then
      if not state.displaced(occupant) then
        state.set_displaced(occupant, target)
      end
      return
    end
    if target._tab == api.nvim_get_current_tabpage() then
      target:show(false)
    end
  end)
end

--- The window went away: a real close of the sidebar (any cause but `hide`).
---@param self Lib.UI.Kit.Sidebar
---@param was_visible boolean
function finish(self, was_visible)
  if self._closed then
    return
  end
  self._closed = true
  unwatch(self)
  -- A hidden sidebar hands what it displaced on to the one that displaced it (`remove`);
  -- only a visible one brings it back itself.
  local target = was_visible and state.take_displaced(self) or nil
  state.remove(self)
  drop_buffer(self.bufnr)
  for _, cb in ipairs(self._on_close) do
    pcall(cb)
  end
  if target and was_visible and not closing_all then
    restore(target)
  end
end

--- Close callbacks and restore when the window closes by any other path (`:q`, `<C-w>o`).
---@param self Lib.UI.Kit.Sidebar
local function watch(self)
  local autocmd = require("lib.nvim.bindings.autocmd")
  local group = autocmd.group("lib_ui_kit_sidebar_" .. self.winid, true)
  self._augroup = group
  autocmd.create("WinClosed", function()
    finish(self, true)
  end, {
    group = group,
    pattern = tostring(self.winid),
    once = true,
    -- One throwaway hook per window, see lib.nvim.ui.kit.surface.
    record = false,
    desc = "lib.nvim.ui.kit.sidebar: lifecycle",
  })
end

--- Close the sidebar's window and keep the rest (buffer, handle, size) for `show`. Refused
--- for the tabpage's last window, which cannot close without taking the tabpage along.
---@param self Lib.UI.Kit.Sidebar
---@return boolean hidden
local function take_off_screen(self)
  if not self:is_visible() then
    return false
  end
  local win = self.winid --[[@as integer]]
  if is_last_window(win) then
    return false
  end
  self.size = self.position == "bottom" and api.nvim_win_get_height(win)
    or api.nvim_win_get_width(win)
  unwatch(self)
  if not pcall(api.nvim_win_close, win, true) or api.nvim_win_is_valid(win) then
    watch(self)
    return false
  end
  return true
end

--- Is the sidebar open and on screen (not closed, not hidden)?
---@return boolean
function Sidebar:is_visible()
  return not self._closed
    and self.winid ~= nil
    and api.nvim_win_is_valid(self.winid)
    and api.nvim_win_get_buf(self.winid) == self.bufnr
end

--- The same as `is_visible` (the surface contract: "the window handle is live").
---@return boolean
function Sidebar:is_valid()
  return self:is_visible()
end

--- Has the sidebar been closed for good (its buffer is gone)?
---@return boolean
function Sidebar:is_closed()
  return self._closed == true
end

--- Show the title in the window bar (themed with the `title` token); nil removes it.
---@param title string|nil
function Sidebar:set_title(title)
  self.title = title
  if self:is_visible() then
    pcall(
      api.nvim_set_option_value,
      "winbar",
      title and winbar_text(title) or "",
      { scope = "local", win = self.winid }
    )
  end
end

--- Move the cursor into the sidebar, showing it first when it is hidden.
function Sidebar:focus()
  if not self:is_visible() and not self:show(false) then
    return
  end
  api.nvim_set_current_win(self.winid)
end

--- Show a hidden sidebar again (same buffer, last size). A visible sidebar at the same
--- position is displaced and remembered (unless this one is not `exclusive`).
---@param enter? boolean  # move the cursor into it (default true)
---@return boolean shown  # false for a closed sidebar or when the split could not be made
function Sidebar:show(enter)
  if self._closed then
    return false
  end
  if self:is_visible() then
    if enter ~= false then
      api.nvim_set_current_win(self.winid)
    end
    return true
  end
  local tab = api.nvim_get_current_tabpage()
  if self.exclusive then
    local occupant = state.visible_at(tab, self.position, self)
    if occupant and take_off_screen(occupant) then
      state.set_displaced(self, occupant)
    end
  end
  local config = { split = SPLIT[self.position], win = -1 }
  if self.position == "bottom" then
    config.height = self.size
  else
    config.width = self.size
  end
  local ok, win = pcall(api.nvim_open_win, self.bufnr, enter ~= false, config)
  if not ok then
    return false
  end
  self.winid = win
  self._tab = tab
  decorate(self)
  watch(self)
  return true
end

--- Take the sidebar off the screen and keep it (buffer, content, handle, size) for `show`.
--- What it displaced comes back. Fails (false) when it is the tabpage's last window.
---@return boolean hidden
function Sidebar:hide()
  if not take_off_screen(self) then
    return false
  end
  local target = state.take_displaced(self)
  if target and not closing_all then
    restore(target)
  end
  return true
end

--- Close the sidebar for good: window, buffer, close callbacks; what it displaced comes back.
function Sidebar:close()
  if self._closed then
    return
  end
  local was_visible = self:is_visible()
  if was_visible then
    unwatch(self)
    -- The tabpage's last window is not closed here (E444 in the last tabpage); deleting the
    -- buffer below then does what `:bwipeout` does there.
    if not is_last_window(self.winid) then
      pcall(api.nvim_win_close, self.winid, true)
    end
  end
  finish(self, was_visible)
end

--- The surface contract's "run the close callbacks once": for a sidebar that is `close`.
function Sidebar:fire_close()
  self:close()
end

--- Open a sidebar, or show the existing one of the same `name` (its content replaced by
--- `lines` when given). Returns the handle, or nil when the split could not be made.
---@param opts? Lib.UI.Kit.SidebarOpts
---@return Lib.UI.Kit.Sidebar|nil
function M.open(opts)
  opts = opts or {}
  local position = opts.position or "left"
  if not SPLIT[position] then
    error(
      ("kit.sidebar: position must be left, right or bottom, got %s"):format(tostring(position)),
      2
    )
  end

  if opts.name then
    local existing = state.get(opts.name)
    if existing and not existing._closed then
      if opts.lines then
        existing:set_lines(opts.lines)
      end
      if not existing:show(opts.enter) then
        return nil
      end
      return existing
    end
  end

  local name = opts.name
  if not name then
    unnamed = unnamed + 1
    name = "sidebar_" .. unnamed
  end

  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  -- "hide": the buffer outlives a hidden window; `close`/`close_all` delete it.
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  if opts.lines then
    api.nvim_buf_set_lines(buf, 0, -1, false, opts.lines)
  end
  if opts.filetype then
    vim.bo[buf].filetype = opts.filetype
  end
  for option, value in pairs(opts.bo or {}) do
    pcall(api.nvim_set_option_value, option, value, { buf = buf })
  end
  vim.bo[buf].modifiable = opts.modifiable == true
  vim.b[buf][M.BUF_VAR] = name

  local self = setmetatable({
    bufnr = buf,
    name = name,
    position = position,
    size = resolve_size(position, opts.size),
    title = opts.title,
    exclusive = opts.exclusive ~= false,
    border = "none",
    _resolved = theme.resolve(opts.theme),
    _wo = opts.wo or {},
    _on_close = {},
    _closed = false,
  }, Sidebar)

  if not self:show(opts.enter) then
    pcall(api.nvim_buf_delete, buf, { force = true })
    return nil
  end
  state.add(self)
  if opts.on_close then
    self:on_close(opts.on_close)
  end
  return self
end

--- Hide the sidebar `opts.name` when it is visible, else show it (opening it with `opts` the
--- first time). The handle, or nil when nothing could be opened.
---@param opts Lib.UI.Kit.SidebarOpts
---@return Lib.UI.Kit.Sidebar|nil
function M.toggle(opts)
  local existing = opts.name and state.get(opts.name)
  if existing and existing:is_visible() then
    existing:hide()
    return existing
  end
  return M.open(opts)
end

--- The handle of the sidebar `name` (open or hidden), or nil.
---@param name string
---@return Lib.UI.Kit.Sidebar|nil
function M.get(name)
  return state.get(name)
end

--- The window showing the sidebar `name`, found by its buffer variable (UI-31): the current
--- tabpage first, then any other. nil when it is hidden or closed.
---@param name string
---@return integer|nil
function M.find(name)
  local function scan(wins)
    for _, win in ipairs(wins) do
      local ok, tag = pcall(function()
        return vim.b[api.nvim_win_get_buf(win)][M.BUF_VAR]
      end)
      if ok and tag == name then
        return win
      end
    end
  end
  return scan(api.nvim_tabpage_list_wins(0)) or scan(api.nvim_list_wins())
end

--- Every sidebar (open or hidden), oldest first.
---@return Lib.UI.Kit.Sidebar[]
function M.list()
  return state.list()
end

--- The one cleanup (UI-52): close every sidebar, visible or hidden, wipe their buffers, run
--- their close callbacks, restore nothing. Safe from an autocmd, an error path or `teardown()`.
function M.close_all()
  closing_all = true
  local ok, err = pcall(function()
    for _, handle in ipairs(state.list()) do
      handle:close()
    end
  end)
  closing_all = false
  if not ok then
    error(err, 0)
  end
end

return M
