---@module 'lib.nvim.ui.statusline'
--- A short status badge pinned to the bottom line of one window.
---
--- The obvious implementation — set that window's `&statusline` — silently
--- shows nothing under `laststatus = 3`, where Neovim draws a single global
--- statusline and no per-window one exists at all. Since a plugin cannot know
--- (or dictate) the user's `laststatus`, a badge that only sometimes appears
--- is not usable. This module resolves the strategy at attach time instead:
---
---   * `"statusline"` — window-local `&statusline`, restored on detach.
---   * `"float"` — a one-line, unfocusable floating window laid over the
---     target window's first or last row (`opts.anchor`, default last),
---     repositioned as the layout changes.
---   * `"auto"` (default) — `"statusline"` while a per-window statusline
---     exists, `"float"` once `laststatus = 3` takes it away.
---
--- `opts.anchor` only affects `"float"`: a window's own `&statusline` is
--- always its last row, there is no top equivalent. A badge that must stay
--- pinned to one edge regardless of `laststatus` (a breadcrumb trail, say,
--- always at the top) should therefore force `mode = "float"` rather than
--- "auto" — "auto" would otherwise alternate between an always-last-row
--- statusline and a `"top"`-anchored float depending on the user's setting.
---
--- The text is deliberately **plain**, with the highlight passed separately:
--- statusline `%#Group#` items mean nothing inside a float's buffer, so a
--- badge that must render identically in both places cannot carry them.
---
---   local statusline = require("lib.nvim.ui.statusline")
---
---   local badge = statusline.attach(winid)
---   badge.set("LOCK  ~/notes", "DiagnosticWarn")
---   badge.clear()
---   badge.detach()
---
--- See @types/init.lua for Lib.UI.Statusline.*.

require("lib.nvim.ui.statusline.@types")

local au = require("lib.nvim.bindings.autocmd")

local M = {}

---Unique suffix per segment; each attachment owns its augroup.
local _seq = 0

---True when Neovim draws one global statusline instead of per-window ones.
---@return boolean
function M.is_global()
  return vim.o.laststatus >= 3
end

---Resolve `"auto"` against the current `laststatus`.
---@param mode Lib.UI.Statusline.Mode?
---@return "statusline"|"float"
function M.resolve_mode(mode)
  -- Returned as literals: comparing an optional against two strings does
  -- not turn the variable itself into the narrower return type.
  if mode == "statusline" then
    return "statusline"
  end
  if mode == "float" then
    return "float"
  end
  return M.is_global() and "float" or "statusline"
end

---@internal
---Render `text` into a statusline expression.
---@param text string
---@param hl string?
---@param align Lib.UI.Statusline.Align?
---@return string
local function as_expression(text, hl, align)
  -- Percent signs in user data would otherwise be read as statusline items.
  -- (`"%%%%"` is a gsub *replacement*: it yields two literal percent signs.)
  local escaped = text:gsub("%%", "%%%%")
  local body = hl and ("%#" .. hl .. "#" .. escaped .. "%*") or escaped
  if align == "right" then
    return "%=" .. body
  elseif align == "center" then
    return "%=" .. body .. "%="
  end
  return body
end

---@internal
---Pad `text` for float rendering, where there are no alignment items.
---@param text string
---@param width integer
---@param align Lib.UI.Statusline.Align?
---@return string
local function as_line(text, width, align)
  local len = vim.fn.strdisplaywidth(text)
  if len >= width then
    return text
  end
  if align == "right" then
    return string.rep(" ", width - len) .. text
  elseif align == "center" then
    local left = math.floor((width - len) / 2)
    return string.rep(" ", left) .. text
  end
  return text
end

---Attach a badge to `winid`.
---@param winid integer
---@param opts? Lib.UI.Statusline.Opts
---@return Lib.UI.Statusline.Segment? segment nil when `winid` is not a valid window
---@return string? err
function M.attach(winid, opts)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return nil, "ui.statusline: invalid window: " .. tostring(winid)
  end
  opts = opts or {}

  local mode = M.resolve_mode(opts.mode)
  local align = opts.align or "left"
  local anchor = opts.anchor or "bottom"

  local detached = false
  local text, hl = "", opts.hl

  -- statusline mode only: what the window had before, restored on detach.
  -- `nil` means "was never set", which must be restored as an empty string —
  -- setting it back to nil would throw.
  local previous = nil
  if mode == "statusline" then
    local ok, value =
      pcall(vim.api.nvim_get_option_value, "statusline", { win = winid, scope = "local" })
    previous = ok and value or ""
  end

  ---@type integer?
  local float_win = nil
  ---@type integer?
  local float_buf = nil

  local function close_float()
    if float_win and vim.api.nvim_win_is_valid(float_win) then
      pcall(vim.api.nvim_win_close, float_win, true)
    end
    float_win = nil
  end

  ---Where the badge belongs: the target window's last screen row, at its left
  ---edge. Editor-relative, so it is only drawable while the target lives in
  ---the current tabpage.
  ---@return table? config
  local function float_config()
    if not vim.api.nvim_win_is_valid(winid) then
      return nil
    end
    if vim.api.nvim_win_get_tabpage(winid) ~= vim.api.nvim_get_current_tabpage() then
      return nil
    end
    local pos = vim.api.nvim_win_get_position(winid)
    local width = vim.api.nvim_win_get_width(winid)
    local height = vim.api.nvim_win_get_height(winid)
    if width <= 0 or height <= 0 then
      return nil
    end
    return {
      relative = "editor",
      row = anchor == "top" and pos[1] or (pos[1] + height - 1),
      col = pos[2],
      width = width,
      height = 1,
      style = "minimal",
      border = "none",
      focusable = false,
      noautocmd = true,
      zindex = opts.zindex or 30,
    }
  end

  local function render_float()
    if detached or text == "" then
      close_float()
      return
    end
    local config = float_config()
    if not config then
      close_float()
      return
    end

    if not float_buf or not vim.api.nvim_buf_is_valid(float_buf) then
      float_buf = vim.api.nvim_create_buf(false, true)
      vim.bo[float_buf].buftype = "nofile"
      vim.bo[float_buf].bufhidden = "hide"
      vim.bo[float_buf].swapfile = false
    end

    local line = as_line(text, config.width, align)
    vim.bo[float_buf].modifiable = true
    vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, { line })
    vim.bo[float_buf].modifiable = false

    if float_win and vim.api.nvim_win_is_valid(float_win) then
      pcall(vim.api.nvim_win_set_config, float_win, config)
    else
      local ok, win = pcall(vim.api.nvim_open_win, float_buf, false, config)
      if not ok then
        float_win = nil
        return
      end
      float_win = win
    end

    if hl then
      pcall(vim.api.nvim_set_option_value, "winhighlight", "Normal:" .. hl, { win = float_win })
    end
  end

  local function render_statusline()
    if not vim.api.nvim_win_is_valid(winid) then
      return
    end
    local value = text == "" and (previous or "") or as_expression(text, hl, align)
    pcall(vim.api.nvim_set_option_value, "statusline", value, { win = winid, scope = "local" })
  end

  local render = mode == "float" and render_float or render_statusline

  _seq = _seq + 1
  local group =
    vim.api.nvim_create_augroup(("lib.nvim.ui.statusline.%d"):format(_seq), { clear = true })

  local segment

  -- The float is positioned in absolute editor coordinates, so any layout
  -- change invalidates it. There is no "window moved" event — resize and
  -- tab/window switches are the observable proxies.
  if mode == "float" then
    au.create(
      { "WinResized", "VimResized", "WinScrolled", "WinEnter", "TabEnter", "WinNew", "WinClosed" },
      function()
        if detached then
          return
        end
        if not vim.api.nvim_win_is_valid(winid) then
          segment.detach()
          return
        end
        render_float()
      end,
      {
        group = group,
        desc = "lib.nvim.ui.statusline: reposition badge",
      }
    )
  else
    au.create("WinClosed", function(args)
      if not detached and tonumber(args.match) == winid then
        segment.detach()
      end
    end, {
      group = group,
      desc = "lib.nvim.ui.statusline: drop badge with its window",
    })
  end

  ---@type Lib.UI.Statusline.Segment
  segment = {
    mode = function()
      return mode
    end,

    text = function()
      return text
    end,

    set = function(new_text, new_hl)
      if detached then
        return
      end
      text = new_text or ""
      if new_hl ~= nil then
        hl = new_hl
      end
      render()
    end,

    clear = function()
      if detached then
        return
      end
      text = ""
      render()
    end,

    refresh = function()
      if not detached then
        render()
      end
    end,

    detach = function()
      if detached then
        return
      end
      detached = true
      pcall(vim.api.nvim_del_augroup_by_id, group)
      close_float()
      if float_buf and vim.api.nvim_buf_is_valid(float_buf) then
        pcall(vim.api.nvim_buf_delete, float_buf, { force = true })
      end
      float_buf = nil
      if mode == "statusline" and vim.api.nvim_win_is_valid(winid) then
        pcall(
          vim.api.nvim_set_option_value,
          "statusline",
          previous or "",
          { win = winid, scope = "local" }
        )
      end
    end,
  }

  return segment
end

---@type Lib.UI.Statusline
return M
