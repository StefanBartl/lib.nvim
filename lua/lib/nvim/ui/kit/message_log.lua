---@module 'lib.nvim.ui.kit.message_log'
--- Scrollable, time-ordered, paginated, collapsible entry list popup --
--- generalizes "show a recent, growing, time-stamped list" (first consumer:
--- debugging.nvim's recent-messages view, backed by lib.nvim.messages).
--- Deliberately knows nothing about where entries come from: plain tables
--- in (`{time_ms, level?, content}`, `time_ms` any clock as long as it's
--- consistent -- monotonic or epoch, this module only ever compares two of
--- the caller's own values), callbacks for "there's more" and live updates.

local surface = require("lib.nvim.ui.kit.surface")
local close_on_focus_lost = require("lib.nvim.window.close_on_focus_lost")

local M = {}

---@internal
local LEVEL_HL = {
  [vim.log.levels.WARN] = "DiagnosticWarn",
  [vim.log.levels.ERROR] = "DiagnosticError",
}

---@internal
---Default "Ns ago" formatter: `now_ms`/`entry.time_ms` must share a clock.
---@param entry table
---@param now_ms number
---@return string
local function default_format_time(entry, now_ms)
  local delta_s = math.max(0, (now_ms - (entry.time_ms or now_ms)) / 1000)
  if delta_s < 60 then
    return ("%ds ago"):format(math.floor(delta_s))
  end
  local m = math.floor(delta_s / 60)
  local s = math.floor(delta_s % 60)
  return ("%dm %ds ago"):format(m, s)
end

---@internal
---One entry -> its rendered line(s). Collapsed: first content line only,
---with a "… (N more lines)" marker when truncated.
---@param entry table
---@param opts Lib.UI.Kit.MessageLog.Opts
---@param collapsed boolean
---@param now_ms number
---@return string[] lines, string|nil hl_group  # hl_group applies to every line of this entry
local function render_entry(entry, opts, collapsed, now_ms)
  local format_time = opts.format_entry_time or default_format_time
  local time_label = format_time(entry, now_ms)
  local content_lines = vim.split(tostring(entry.content or ""), "\n", { plain = true })
  local hl = entry.level and LEVEL_HL[entry.level] or nil

  local lines = { ("[%s] %s"):format(time_label, content_lines[1] or "") }
  if collapsed then
    if #content_lines > 1 then
      lines[1] = lines[1]
        .. ("  … (+%d more line%s)"):format(
          #content_lines - 1,
          #content_lines - 1 == 1 and "" or "s"
        )
    end
  else
    for i = 2, #content_lines do
      lines[#lines + 1] = content_lines[i]
    end
  end
  return lines, hl
end

---@class Lib.UI.Kit.MessageLog.Handle
---@field package surf Lib.UI.Kit.Surface
---@field package opts Lib.UI.Kit.MessageLog.Opts
---@field package entries table[]  oldest first
---@field package collapsed boolean
---@field package has_more_older boolean
---@field package has_more_newer boolean
local Handle = {}
Handle.__index = Handle

---@internal
---Full re-render: order, collapse, line-highlights, pagination hints.
function Handle:_redraw()
  local ordered = self.entries
  if self.opts.order == "newest_first" then
    ordered = {}
    for i = #self.entries, 1, -1 do
      ordered[#ordered + 1] = self.entries[i]
    end
  end

  local now_ms = self.now_ms_fn()
  local lines, highlights = {}, {}
  for _, entry in ipairs(ordered) do
    local entry_lines, hl = render_entry(entry, self.opts, self.collapsed, now_ms)
    if hl then
      for i = 1, #entry_lines do
        highlights[#lines + i] = hl
      end
    end
    for _, l in ipairs(entry_lines) do
      lines[#lines + 1] = l
    end
  end
  if #lines == 0 then
    lines = { "(no messages)" }
  end

  self.surf:set_lines(lines)

  if vim.api.nvim_buf_is_valid(self.surf.bufnr) then
    vim.api.nvim_buf_clear_namespace(self.surf.bufnr, self._hl_ns, 0, -1)
    for lnum, hl in pairs(highlights) do
      pcall(vim.api.nvim_buf_add_highlight, self.surf.bufnr, self._hl_ns, hl, lnum - 1, 0, -1)
    end
    pcall(vim.api.nvim_buf_clear_namespace, self.surf.bufnr, self._arrow_ns, 0, -1)
    if self.has_more_older then
      pcall(vim.api.nvim_buf_set_extmark, self.surf.bufnr, self._arrow_ns, 0, 0, {
        virt_lines = { { { "󰁝 more above -- <C-k>", "Comment" } } },
        virt_lines_above = true,
      })
    end
    if self.has_more_newer then
      pcall(vim.api.nvim_buf_set_extmark, self.surf.bufnr, self._arrow_ns, #lines - 1, 0, {
        virt_lines = { { { "󰁅 more below -- <C-j>", "Comment" } } },
      })
    end
  end
end

---Append newly-arrived entries (a live feed) without discarding history
---already loaded. The caller owns its own subscription to its data source
---and is responsible for only calling this with entries that belong here
---(already filtered/ordered the way the caller wants).
---@param new_entries table[]
function Handle:append(new_entries)
  if not self.surf:is_valid() or #new_entries == 0 then
    return
  end
  for _, e in ipairs(new_entries) do
    self.entries[#self.entries + 1] = e
  end
  self:_redraw()
end

---Load older or newer entries via `opts.load_more`, prepending/appending
---them. Hides that direction's pagination hint once `load_more` reports
---nothing left (an empty return).
---@param direction "older"|"newer"
function Handle:load_more(direction)
  if type(self.opts.load_more) ~= "function" then
    return
  end
  local more = self.opts.load_more(direction) or {}
  if #more == 0 then
    if direction == "older" then
      self.has_more_older = false
    else
      self.has_more_newer = false
    end
    self:_redraw()
    return
  end
  if direction == "older" then
    local merged = {}
    for _, e in ipairs(more) do
      merged[#merged + 1] = e
    end
    for _, e in ipairs(self.entries) do
      merged[#merged + 1] = e
    end
    self.entries = merged
  else
    for _, e in ipairs(more) do
      self.entries[#self.entries + 1] = e
    end
  end
  self:_redraw()
end

---Toggle collapsed mode (first-line-only per entry).
---@param value? boolean  # explicit state; omit to flip
function Handle:set_collapsed(value)
  self.collapsed = value == nil and not self.collapsed or value == true
  self:_redraw()
end

---Register a callback for when the window closes (any cause).
---@param cb fun()
function Handle:on_close(cb)
  self.surf:on_close(cb)
end

function Handle:close()
  self.surf:close()
end

---@internal
local function show_cheatsheet(parent_opts)
  local lines = {
    "q / <Esc>   close",
    "<C-j>       load older entries",
    "<C-k>       load newer entries",
    "<C-l>       expand (un-collapse)",
    "<C-h>       collapse",
    "<C-e>       toggle collapsed mode",
    "?           this cheatsheet",
  }
  for _, extra in ipairs(parent_opts.extra_cheatsheet_lines or {}) do
    lines[#lines + 1] = extra
  end
  require("lib.nvim.ui.kit.viewer").open({ title = "message log -- keys", lines = lines })
end

---Open the popup. Returns nil if the underlying window could not be
---created (same failure contract as `lib.nvim.ui.kit.surface.open`).
---@param opts Lib.UI.Kit.MessageLog.Opts
---@return Lib.UI.Kit.MessageLog.Handle|nil
function M.open(opts)
  opts = opts or {}
  local now_ms_fn = opts.now_ms or function()
    return vim.uv.hrtime() / 1e6
  end

  local surf = surface.open({
    lines = { "" },
    theme = opts.theme,
    title = opts.title,
    width = opts.width,
    height = opts.height,
    relative = opts.relative or "editor",
    nice_quit = true,
    enter = true,
    filetype = opts.filetype or "ui-kit-message-log",
    modifiable = false,
  })
  if not surf then
    return nil
  end

  local self = setmetatable({
    surf = surf,
    opts = opts,
    entries = vim.deepcopy(opts.entries or {}),
    collapsed = opts.collapsed_default == true,
    has_more_older = type(opts.load_more) == "function",
    has_more_newer = false, -- newest loaded entry is "now"; nothing newer until a live append arrives
    now_ms_fn = now_ms_fn,
    _hl_ns = vim.api.nvim_create_namespace("ui_kit_message_log_hl_" .. surf.bufnr),
    _arrow_ns = vim.api.nvim_create_namespace("ui_kit_message_log_arrows_" .. surf.bufnr),
  }, Handle)

  if opts.close_on_focus_lost ~= false then
    close_on_focus_lost(surf.winid)
  end

  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = surf.bufnr, nowait = true, silent = true })
  end
  map("<C-j>", function()
    self:load_more("older")
  end)
  map("<C-k>", function()
    self:load_more("newer")
  end)
  map("<C-l>", function()
    self:set_collapsed(false)
  end)
  map("<C-h>", function()
    self:set_collapsed(true)
  end)
  map("<C-e>", function()
    self:set_collapsed()
  end)
  map("?", function()
    show_cheatsheet(opts)
  end)

  self:_redraw()
  return self
end

---@type Lib.UI.Kit.MessageLogModule
return M
