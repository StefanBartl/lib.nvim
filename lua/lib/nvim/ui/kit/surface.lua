---@module 'lib.nvim.ui.kit.surface'
--- A surface is one themed floating window plus a lifecycle handle. It hands
--- geometry/buffer creation to lib.nvim.window.make_scratch and then applies the
--- resolved theme; it does not re-implement float creation.

local make_scratch = require("lib.nvim.window.make_scratch")
local set_title = require("lib.nvim.window.set_title")
local theme = require("lib.nvim.ui.kit.theme")

local api = vim.api

---@class Lib.UI.Kit.Surface
---@field package _on_close function[]
---@field package _closed boolean
local Surface = {}
Surface.__index = Surface

---@param lines string[]
function Surface:set_lines(lines)
  if not api.nvim_buf_is_valid(self.bufnr) then
    return
  end
  local was_modifiable = api.nvim_get_option_value("modifiable", { buf = self.bufnr })
  api.nvim_set_option_value("modifiable", true, { buf = self.bufnr })
  api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)
  api.nvim_set_option_value("modifiable", was_modifiable, { buf = self.bufnr })
end

---@param title string|nil
function Surface:set_title(title)
  if api.nvim_win_is_valid(self.winid) then
    set_title(self.winid, title)
  end
end

function Surface:focus()
  if api.nvim_win_is_valid(self.winid) then
    api.nvim_set_current_win(self.winid)
  end
end

---@param cb fun()
function Surface:on_close(cb)
  if type(cb) == "function" then
    self._on_close[#self._on_close + 1] = cb
  end
end

---@return boolean
function Surface:is_valid()
  return api.nvim_win_is_valid(self.winid)
end

--- Run the close callbacks exactly once.
function Surface:fire_close()
  if self._closed then
    return
  end
  self._closed = true
  for _, cb in ipairs(self._on_close) do
    pcall(cb)
  end
end

function Surface:close()
  if api.nvim_win_is_valid(self.winid) then
    pcall(api.nvim_win_close, self.winid, true)
  end
  self:fire_close()
end

local M = {}

--- Open a themed float and return its handle (or nil on failure).
---@param opts? Lib.UI.Kit.SurfaceOpts
---@return Lib.UI.Kit.Surface|nil
function M.open(opts)
  opts = opts or {}
  local resolved = theme.resolve(opts.theme)

  local winid, bufnr = make_scratch({
    lines = opts.lines,
    width = opts.width,
    height = opts.height,
    relative = opts.relative,
    row = opts.row,
    col = opts.col,
    border = resolved.border,
    title = opts.title,
    title_pos = opts.title_pos or resolved.title_pos,
    zindex = opts.zindex or resolved.zindex.popup,
    focusable = opts.focusable,
    enter = opts.enter,
    filetype = opts.filetype,
    modifiable = opts.modifiable,
    nice_quit = opts.nice_quit,
    wo = opts.wo,
    bo = opts.bo,
  })

  if not winid or not bufnr then
    return nil
  end

  theme.apply(winid, resolved)

  local self = setmetatable({
    winid = winid,
    bufnr = bufnr,
    _on_close = {},
    _closed = false,
  }, Surface)

  -- Fire on_close callbacks when the window closes for any reason.
  local group = api.nvim_create_augroup("lib_ui_kit_surface_" .. winid, { clear = true })
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(winid),
    once = true,
    callback = function()
      self:fire_close()
    end,
    desc = "lib.nvim.ui.kit.surface: lifecycle",
  })

  return self
end

return M
