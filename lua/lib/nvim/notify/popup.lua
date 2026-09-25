---@module 'lib.nvim.notify.popup'
---@brief Popup delivery for notifications: a corner toast plus a yankable history.
---@description
--- `vim.notify` on a plain Neovim UI is `nvim_echo`, so long or multi-line text
--- (a rejected `git push`, say) pops up as a `:messages` / more-prompt and
--- steals focus. This module shows the message as a non-focus-stealing
--- `ui.kit` toast in the top-right corner instead -- wrapped to the toast
--- width and colored by level -- and keeps every message in a bounded history
--- that opens in a scratch buffer, so the full text can be yanked later.
---
--- Delivery order for a message:
---   1. recorded in the history (always)
---   2. if `ui.notify` (ui.nvim) is enabled it already turns `vim.notify` into
---      toasts, so the message is handed to `vim.notify` to avoid a second popup
---   3. else shown via `ui.kit.toast` (soft dependency on ui.nvim)
---   4. else, when no toast can be shown, `vim.notify` -- a message is never lost
---
--- Use it through `require("lib.nvim.notify").create(prefix, { popup = true })`
--- or call `deliver` directly.

---@class Lib.Notify.Popup
local M = {}

local WIDTH = 38 -- ui.kit toasts are 40 columns wide, minus the border
local MAX_LINES = 12
local HISTORY_MAX = 200

-- Per level: title, toast highlight group, milliseconds on screen.
local LEVELS = {
  [vim.log.levels.TRACE] = { name = "trace", hl = "Comment", timeout = 3000 },
  [vim.log.levels.DEBUG] = { name = "debug", hl = "Comment", timeout = 3000 },
  [vim.log.levels.INFO] = { name = "info", hl = "DiagnosticInfo", timeout = 4000 },
  [vim.log.levels.WARN] = { name = "warn", hl = "DiagnosticWarn", timeout = 6000 },
  [vim.log.levels.ERROR] = { name = "error", hl = "DiagnosticError", timeout = 10000 },
}

---@class Lib.Notify.Popup.Entry
---@field time string
---@field level integer
---@field message string
---@field source string|nil

---@class Lib.Notify.Popup.Opts
---@field source? string Tag for the history and the toast title (e.g. "reposcope")
---@field timeout? integer Toast lifetime in ms (default per level)

---@type Lib.Notify.Popup.Entry[]
local history = {}

---Hard-wraps `text` to `width` display columns and caps the line count.
---@param text string
---@param width integer
---@param max_lines integer
---@return string[]
local function wrap(text, width, max_lines)
  local out = {}
  for _, raw in ipairs(vim.split(text, "\n", { plain = true })) do
    local line = raw:gsub("\t", "  "):gsub("%s+$", "")
    if line == "" then
      out[#out + 1] = ""
    else
      while vim.fn.strdisplaywidth(line) > width do
        -- Prefer a break at the last space inside the window.
        local cut = width
        local head = vim.fn.strcharpart(line, 0, width)
        local space = head:match("^.*() ")
        if space and space > width / 3 then
          cut = space - 1
        end
        out[#out + 1] = vim.fn.strcharpart(line, 0, cut)
        line = vim.fn.strcharpart(line, cut):gsub("^%s+", "")
      end
      out[#out + 1] = line
    end
  end
  if #out > max_lines then
    out = vim.list_slice(out, 1, max_lines)
    out[max_lines] = "... (full text: the popup history)"
  end
  return out
end

---True when ui.nvim's `ui.notify` already routes `vim.notify` into toasts.
---@return boolean
local function ui_notify_active()
  local ok, ui_notify = pcall(require, "ui.notify")
  return ok and type(ui_notify.is_enabled) == "function" and ui_notify.is_enabled() or false
end

---@param message string
---@param level integer
---@param opts Lib.Notify.Popup.Opts
---@return boolean shown
local function show_toast(message, level, opts)
  local ok_toast, toast = pcall(require, "ui.kit.toast")
  if not ok_toast then
    return false
  end

  local spec = LEVELS[level] or LEVELS[vim.log.levels.INFO]
  local title = (opts.source and (opts.source .. " ") or "") .. spec.name
  local ok = pcall(toast.open, {
    title = title,
    message = wrap(message, WIDTH, MAX_LINES),
    timeout = opts.timeout or spec.timeout,
    theme = { hl = { border = spec.hl, title = spec.hl } },
  })
  return ok
end

---Records `message` and shows it as a popup.
---@param message string
---@param level? integer vim.log.levels value (default: INFO)
---@param opts? Lib.Notify.Popup.Opts
---@return nil
function M.deliver(message, level, opts)
  level = level or vim.log.levels.INFO
  opts = opts or {}
  message = tostring(message)

  history[#history + 1] =
    { time = os.date("%H:%M:%S"), level = level, message = message, source = opts.source }
  if #history > HISTORY_MAX then
    table.remove(history, 1)
  end

  if ui_notify_active() or not show_toast(message, level, opts) then
    vim.notify(message, level)
  end
end

---Matches an entry against an optional source filter.
---@param entry Lib.Notify.Popup.Entry
---@param source string|nil
---@return boolean
local function matches(entry, source)
  return source == nil or entry.source == source
end

---The recorded messages, oldest first.
---@param source? string Only messages delivered with this source
---@return Lib.Notify.Popup.Entry[]
function M.history(source)
  if source == nil then
    return history
  end
  return vim.tbl_filter(function(entry)
    return matches(entry, source)
  end, history)
end

---Forgets recorded messages.
---@param source? string Only forget messages of this source (default: all)
---@return nil
function M.clear(source)
  if source == nil then
    history = {}
    return
  end
  history = vim.tbl_filter(function(entry)
    return not matches(entry, source)
  end, history)
end

---Opens the history in a scratch buffer (newest last) so it can be yanked.
---@param source? string Only show messages of this source
---@return integer bufnr
function M.show_history(source)
  local lines = {}
  for _, entry in ipairs(M.history(source)) do
    local spec = LEVELS[entry.level] or LEVELS[vim.log.levels.INFO]
    local prefix = ("%s %-5s "):format(entry.time, spec.name:upper())
    local pad = (" "):rep(#prefix)
    for i, text in ipairs(vim.split(entry.message, "\n", { plain = true })) do
      lines[#lines + 1] = (i == 1 and prefix or pad) .. text
    end
  end
  if #lines == 0 then
    lines = { "(no messages yet)" }
  end

  vim.cmd("botright new")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_set_name(buf, "notify://" .. (source or "messages"))
  vim.cmd("normal! G")
  vim.keymap.set(
    "n",
    "q",
    "<Cmd>close<CR>",
    { buffer = buf, silent = true, desc = "Close message history" }
  )
  return buf
end

return M
