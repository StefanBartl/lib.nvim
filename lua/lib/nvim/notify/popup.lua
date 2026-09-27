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

local fast_event = require("lib.nvim.notify.internal.fast_event")

---@class Lib.Notify.Popup
local M = {}

---@class Lib.Notify.Popup.Config
---@field messages boolean Also record every message in `:messages` (default: true)
---@field max_lines integer Toast line cap (default 12)
---@field width integer Toast wrap width in columns (default 38; ui.kit toasts are 40 columns wide, minus the border)
---@field toast_max_bytes integer Bytes of a message considered when wrapping for the toast (default 4000); a message can be arbitrarily large (a whole command's output) but only its head is ever shown in a toast
---@field entry_max_bytes integer Bytes kept per history entry (default 64 KiB)
---@field toast_min_level integer Below this vim.log.levels value: recorded in history/`:messages` only, no toast (default INFO)
---@field timeouts table<integer, integer> Per-level toast lifetime override in ms, merged over `LEVELS[*].timeout`
---@field history_full boolean `show_history()` shows entries in full instead of collapsed to `max_lines` (default false)

---Partial form of `Lib.Notify.Popup.Config` accepted by `M.setup`: every
---field optional, a field left unset keeps its current value.
---@class Lib.Notify.Popup.SetupOpts
---@field messages? boolean
---@field max_lines? integer
---@field width? integer
---@field toast_max_bytes? integer
---@field entry_max_bytes? integer
---@field toast_min_level? integer
---@field timeouts? table<integer, integer>
---@field history_full? boolean

---@type Lib.Notify.Popup.Config
local config = {
  messages = true,
  max_lines = 12,
  width = 38,
  toast_max_bytes = 4000,
  entry_max_bytes = 64 * 1024,
  toast_min_level = vim.log.levels.INFO,
  timeouts = {},
  history_full = false,
}

local HISTORY_MAX = 200 -- capped number of entries kept, independent of config

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
---@field source? string Tag for the history and, absent an explicit `title`, the toast title (e.g. "reposcope")
---@field title? string Overrides the toast's default `source level-name` title (e.g. "sessions.marks"); also passed to the plain `vim.notify` fallback so a rich backend still sees it
---@field timeout? integer Toast lifetime in ms (default per level, or config.timeouts[level])
---@field messages? boolean Override the module default for writing to `:messages`
---@field max_lines? integer Override config.max_lines for this call
---@field width? integer Override config.width for this call
---@field toast_max_bytes? integer Override config.toast_max_bytes for this call
---@field entry_max_bytes? integer Override config.entry_max_bytes for this call
---@field toast_min_level? integer Override config.toast_min_level for this call

---@type Lib.Notify.Popup.Entry[]
local history = {}
---@type Lib.Notify.Popup.Entry|nil
local last_entry = nil

---Hard-wraps `text` to `width` display columns and caps the line count.
---@param text string
---@param width integer
---@param max_lines integer
---@param max_bytes integer Bytes of `text` considered before wrapping
---@return string[]
local function wrap(text, width, max_lines, max_bytes)
  -- A caller-supplied max_lines of 0 (or negative) would make
  -- vim.list_slice(out, 1, max_lines) return an empty table below, and the
  -- truncation marker would then land on out[0] -- invisible to ipairs/#,
  -- silently losing the whole message instead of showing at least one line.
  max_lines = math.max(1, max_lines)
  local truncated = false
  if #text > max_bytes then
    text = text:sub(1, max_bytes)
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
    out[#out] = "... (:Lib notify last)"
  end
  return out
end

local MSG_HL = {
  [vim.log.levels.WARN] = "WarningMsg",
  [vim.log.levels.ERROR] = "ErrorMsg",
}

---Adds `message` to `:messages` (the message history).
---
---A previous version of this function ran `:silent! echohl X | echomsg "..."
---| echohl None` through `vim.cmd`, on the theory that `:silent!` would
---suppress the on-screen echo while `:echomsg` still recorded into
---|message-history|. It did not: a command modifier such as `:silent` only
---applies to the FIRST bar (`|`)-separated command on the line (see
---`:h :verbose-cmd`'s own worked example), so the `echomsg` clause ran
---completely unsilenced -- every delivery with the default `messages = true`
---was, in practice, an ordinary visible echo, for any message length. And
---repeating `silent!` on every clause is not a fix either (verified
---directly): `:silent` does not just suppress display, it also stops the
---message from being added to history at all (see `:h :silent`), so that
---"fix" would have silently defeated this function's entire purpose instead.
---
---Neovim has no API to add a message to |message-history| without ever
---touching the screen -- `nvim_echo(..., true, {})` is the only way to
---record one, and it echoes as it records. This calls that directly instead
---of going through a hand-built Ex command: it removes both the `:silent`
---scoping bug above and any question of escaping `message` into a Vimscript
---string literal safely (there is no command string left to build). `more`
---is toggled off for the call so a long or multi-line message can never
---block on a `--More--` prompt.
---
---An earlier version instead attached a throwaway `ext_messages` UI
---consumer (`vim.ui_attach`) for the call, specifically to swallow the
---on-screen echo while still recording history. That approach is dropped:
---`vim.ui_attach` is documented as experimental/unstable, and it was found
---to hang indefinitely -- never returning -- once any floating window was
---already open; a `pcall` around it only catches errors, not a call that
---never comes back, so it gave no real protection against that.
---
---A message that must never be echoed at all -- not even briefly -- should
---pass `messages = false` instead of relying on this function to hide it.
---@param message string
---@param level integer
---@return nil
local write_messages = fast_event.guard(function(message, level)
  local hl = MSG_HL[level] or "None"
  local more = vim.o.more
  vim.o.more = false
  pcall(vim.api.nvim_echo, { { message, hl } }, true, {})
  vim.o.more = more
end)

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
  local title = opts.title or ((opts.source and (opts.source .. " ") or "") .. spec.name)
  local width = opts.width or config.width
  local max_lines = opts.max_lines or config.max_lines
  local max_bytes = opts.toast_max_bytes or config.toast_max_bytes
  local timeout = opts.timeout or config.timeouts[level] or spec.timeout
  local ok = pcall(toast.open, {
    title = title,
    message = wrap(message, width, max_lines, max_bytes),
    timeout = timeout,
    theme = { hl = { border = spec.hl, title = spec.hl } },
  })
  return ok
end

---Records `message` and shows it as a popup.
---@param message string
---@param level? integer vim.log.levels value (default: INFO)
---@param opts? Lib.Notify.Popup.Opts
---@return nil
M.deliver = fast_event.guard(function(message, level, opts)
  level = level or vim.log.levels.INFO
  opts = opts or {}
  -- A message containing a raw NUL crosses the vim.fn bridge as a Blob, not a
  -- String -- wrap()'s vim.fn.strdisplaywidth/strcharpart/strchars calls then
  -- raise E976 and this whole delivery is lost. A message can be arbitrary
  -- command output (see toast_max_bytes above), so a stray NUL is realistic.
  message = tostring(message):gsub("%z", "\\0")
  local entry_max = opts.entry_max_bytes or config.entry_max_bytes
  if #message > entry_max then
    message = message:sub(1, entry_max) .. "\n... (truncated)"
  end

  ---@type Lib.Notify.Popup.Entry
  local entry = {
    time = os.date("%H:%M:%S") --[[@as string]],
    level = level,
    message = message,
    source = opts.source,
  }
  history[#history + 1] = entry
  last_entry = entry
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

  -- Below toast_min_level: stays in history/:messages only. This is what
  -- keeps a chatty plugin (dozens of INFO-level lib_notify call sites) from
  -- spamming the corner -- deliberately skips vim.notify too, not just the
  -- toast, since either would still be a visible popup on a plain UI.
  local toast_min_level = opts.toast_min_level or config.toast_min_level
  if level < toast_min_level then
    return
  end

  if ui_notify_active() or not show_toast(message, level, opts) then
    -- Handing off to vim.notify -- either because a rich backend (ui.notify)
    -- already turns it into a toast, or because no toast could be shown --
    -- is also the caller's only remaining chance to see its title: forward
    -- it the same way a plain vim.notify() call would have taken it.
    vim.notify(message, level, opts.title and { title = opts.title } or nil)
  end
end)

---Changes module-wide defaults.
---@param opts? Lib.Notify.Popup.SetupOpts `timeouts` merges per level rather
---than replacing the whole table.
---@return nil
function M.setup(opts)
  opts = opts or {}
  if opts.messages ~= nil then
    config.messages = opts.messages and true or false
  end
  if opts.max_lines ~= nil then
    config.max_lines = opts.max_lines
  end
  if opts.width ~= nil then
    config.width = opts.width
  end
  if opts.toast_max_bytes ~= nil then
    config.toast_max_bytes = opts.toast_max_bytes
  end
  if opts.entry_max_bytes ~= nil then
    config.entry_max_bytes = opts.entry_max_bytes
  end
  if opts.toast_min_level ~= nil then
    config.toast_min_level = opts.toast_min_level
  end
  if opts.timeouts ~= nil then
    for lvl, ms in pairs(opts.timeouts) do
      config.timeouts[lvl] = ms
    end
  end
  if opts.history_full ~= nil then
    config.history_full = opts.history_full and true or false
  end
end

---Opens the last delivered message in full, in a read-only viewer panel
---(yankable, `q`/`<Esc>` closes). No-op when nothing has been delivered yet.
---@return nil
function M.expand_last()
  if not last_entry then
    return
  end
  require("lib.nvim.ui.kit.viewer").open({
    lines = vim.split(last_entry.message, "\n", { plain = true }),
    title = last_entry.source or "notify",
  })
end

---Toggles `config.history_full` (collapsed vs. full entries in
---`show_history()`). Exposed separately from `setup` so a keymap -- the
---buffer-local `<C-s>` in a history buffer, or a global one from the user's
---own config -- can flip it without reading the current value back out.
---@return nil
function M.toggle_full()
  config.history_full = not config.history_full
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
    last_entry = nil
    return
  end
  history = vim.tbl_filter(function(entry)
    return not matches(entry, source)
  end, history)
  if last_entry and matches(last_entry, source) then
    last_entry = nil
  end
end

---Renders the recorded messages (optionally filtered by `source`) into
---display lines, prefixed with time and level. Collapsed to `config.max_lines`
---per entry (plus a `[+N lines, <C-s>]` marker) unless `config.history_full`.
---@param source? string
---@return string[]
local function render_history_lines(source)
  local lines = {}
  for _, entry in ipairs(M.history(source)) do
    local spec = LEVELS[entry.level] or LEVELS[vim.log.levels.INFO]
    local prefix = ("%s %-5s "):format(entry.time, spec.name:upper())
    local pad = (" "):rep(#prefix)
    local entry_lines = vim.split(entry.message, "\n", { plain = true })
    if not config.history_full and #entry_lines > config.max_lines then
      local hidden = #entry_lines - config.max_lines
      entry_lines = vim.list_slice(entry_lines, 1, config.max_lines)
      entry_lines[#entry_lines + 1] = ("[+%d lines, <C-s>]"):format(hidden)
    end
    for i, text in ipairs(entry_lines) do
      lines[#lines + 1] = (i == 1 and prefix or pad) .. text
    end
  end
  if #lines == 0 then
    lines = { "(no messages yet)" }
  end
  return lines
end

---Opens the history in a scratch buffer (newest last) so it can be yanked.
---`<C-s>` (buffer-local) toggles collapsed/full entries, same effect as
---`M.toggle_full()`.
---@param source? string Only show messages of this source
---@return integer bufnr
function M.show_history(source)
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

  local function render()
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, render_history_lines(source))
    vim.bo[buf].modifiable = false
  end
  render()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_name(buf, name)
  vim.cmd("normal! G")
  vim.keymap.set(
    "n",
    "q",
    "<Cmd>close<CR>",
    { buffer = buf, silent = true, desc = "Close message history" }
  )
  vim.keymap.set("n", "<C-s>", function()
    M.toggle_full()
    render()
  end, { buffer = buf, nowait = true, silent = true, desc = "Toggle collapsed/full messages" })
  return buf
end

---The `:Lib notify …` routes, for `lib.nvim_usrcmds` to merge into the `:Lib`
---verb it already builds. Exposed as data rather than registered here so
---there is exactly one place that owns the `:Lib` verb (same pattern as
---`lib.nvim.deps.routes()`).
---@return table[] routes
function M.routes()
  return {
    {
      path = { "notify", "last" },
      desc = "Show the last delivered message in full (viewer)",
      run = function()
        M.expand_last()
      end,
    },
    {
      path = { "notify", "history" },
      args = { { name = "source", type = "STRING", optional = true } },
      desc = "Open the notify history (optionally filtered by source)",
      run = function(ctx)
        M.show_history(ctx.args.source)
      end,
    },
    {
      path = { "notify", "clear" },
      args = { { name = "source", type = "STRING", optional = true } },
      desc = "Clear the notify history (optionally by source)",
      run = function(ctx)
        M.clear(ctx.args.source)
      end,
    },
  }
end

return M
