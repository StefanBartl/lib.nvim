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
---   1. recorded in the popup history (always)
---   1b. written to `:messages` too (default; `messages = false` turns it off),
---      without displaying it -- see `write_messages`
---   2. if `ui.notify` (ui.nvim) is enabled it already turns `vim.notify` into
---      toasts, so the message is handed to `vim.notify` to avoid a second popup
---   3. else shown via `ui.kit.toast` (soft dependency on ui.nvim)
---   4. else, when no toast can be shown, `vim.notify` -- a message is never lost
---
--- Use it through `require("lib.nvim.notify").create(prefix, { popup = true })`
--- or call `deliver` directly.

---@class Lib.Notify.Popup
local M = {}

---@class Lib.Notify.Popup.Config
---@field messages boolean Also record every message in `:messages` (default: true)

---@type Lib.Notify.Popup.Config
local config = { messages = true }

local WIDTH = 38 -- ui.kit toasts are 40 columns wide, minus the border
local MAX_LINES = 12
local HISTORY_MAX = 200
-- A message can be arbitrarily large (a whole command's output). Only its head
-- is ever shown in a toast, and the history keeps a bounded copy per entry.
local TOAST_INPUT_MAX = 4000 -- bytes considered when wrapping for the toast
local ENTRY_MAX = 64 * 1024 -- bytes kept per history entry

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
---@field messages? boolean Override the module default for writing to `:messages`

---@type Lib.Notify.Popup.Entry[]
local history = {}

---Hard-wraps `text` to `width` display columns and caps the line count.
---@param text string
---@param width integer
---@param max_lines integer
---@return string[]
local function wrap(text, width, max_lines)
  local truncated = false
  if #text > TOAST_INPUT_MAX then
    text = text:sub(1, TOAST_INPUT_MAX)
    truncated = true
  end

  local out = {}
  for _, raw in ipairs(vim.split(text, "\n", { plain = true })) do
    local line = raw:gsub("\t", "  "):gsub("%s+$", "")
    if line == "" then
      out[#out + 1] = ""
    else
      while vim.fn.strdisplaywidth(line) > width do
        -- Prefer a break at the last space inside the window. `cut` counts
        -- characters (strcharpart), while the match position is a byte index,
        -- so convert before comparing.
        local cut = width
        local head = vim.fn.strcharpart(line, 0, width)
        local space = head:match("^.*() ")
        if space then
          local chars = vim.fn.strchars(head:sub(1, space - 1))
          if chars > width / 3 then
            cut = chars
          end
        end
        out[#out + 1] = vim.fn.strcharpart(line, 0, cut)
        line = vim.fn.strcharpart(line, cut):gsub("^%s+", "")
        if #out > max_lines then
          break
        end
      end
      out[#out + 1] = line
    end
    if #out > max_lines then
      break
    end
  end

  if #out > max_lines or truncated then
    out = vim.list_slice(out, 1, max_lines)
    out[#out] = "... (full text: the popup history)"
  end
  return out
end

local MSG_HL = {
  [vim.log.levels.WARN] = "WarningMsg",
  [vim.log.levels.ERROR] = "ErrorMsg",
}

---Adds `message` to `:messages` (the message history) without showing it.
---
---`nvim_echo(..., true, {})` records the message but also displays it, which
---for multi-line text is exactly the more-prompt this module avoids. The
---display is suppressed by attaching a throwaway `ext_messages` handler for
---the duration of the call: the native UI then receives nothing, while the
---history entry is still written. Messages are unaffected outside the call.
---
---An additional `ext_messages` consumer (noice.nvim and the like) still gets
---the message -- that is their contract with Neovim and cannot be prevented
---from here; such setups can turn this off with `messages = false`.
---@param message string
---@param level integer
---@return nil
local function write_messages(message, level)
  if vim.in_fast_event() then
    vim.schedule(function()
      write_messages(message, level)
    end)
    return
  end

  local ns = vim.api.nvim_create_namespace("lib_nvim_notify_popup")
  local attached = pcall(vim.ui_attach, ns, { ext_messages = true }, function()
    return true
  end)
  if not attached then
    return -- nothing safe to do: writing history would display it
  end
  pcall(vim.api.nvim_echo, { { message, MSG_HL[level] } }, true, {})
  pcall(vim.ui_detach, ns)
end

---True when ui.nvim's `ui.notify` already routes `vim.notify` into toasts.
---@return boolean
local function ui_notify_active()
  -- `ui.notify` is loaded by whoever enabled it; looking at package.loaded
  -- neither pays for a failed rtp search per message nor loads it as a side
  -- effect.
  local ui_notify = package.loaded["ui.notify"]
  return type(ui_notify) == "table"
      and type(ui_notify.is_enabled) == "function"
      and ui_notify.is_enabled()
    or false
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
  -- vim.fn / nvim_* calls below are not allowed in a fast event (libuv
  -- callback); re-enter on the main loop instead of failing.
  if vim.in_fast_event() then
    vim.schedule(function()
      M.deliver(message, level, opts)
    end)
    return
  end

  level = level or vim.log.levels.INFO
  opts = opts or {}
  message = tostring(message)
  if #message > ENTRY_MAX then
    message = message:sub(1, ENTRY_MAX) .. "\n... (truncated)"
  end

  history[#history + 1] =
    { time = os.date("%H:%M:%S"), level = level, message = message, source = opts.source }
  if #history > HISTORY_MAX then
    table.remove(history, 1)
  end

  -- Resolved into a local: `opts` belongs to the caller, who may reuse it, and
  -- writing the default into it would freeze a later `setup({ messages = ... })`
  -- out of that table.
  local to_messages = opts.messages
  if to_messages == nil then
    to_messages = config.messages
  end
  if to_messages then
    write_messages(message, level)
  end

  if ui_notify_active() or not show_toast(message, level, opts) then
    vim.notify(message, level)
  end
end

---Changes module-wide defaults.
---@param opts? { messages?: boolean } `messages = false` stops writing to `:messages`
---@return nil
function M.setup(opts)
  opts = opts or {}
  if opts.messages ~= nil then
    config.messages = opts.messages and true or false
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
    return vim.list_slice(history)
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

  -- A buffer name is unique: reopening while the previous history buffer is
  -- still around would fail with E95, so retire the old one first.
  local name = "notify://" .. (source or "messages")
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b) == name then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end

  vim.cmd("botright new")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_set_name(buf, name)
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
