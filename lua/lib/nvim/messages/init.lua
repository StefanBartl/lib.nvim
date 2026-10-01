---@module 'lib.nvim.messages'
---@brief Time-stamped message/event ring buffer -- the data source behind a
---"recent messages" popup. No UI at all; a renderer (ui.nvim) queries it.
---@description
--- Two feeds write into the same ring buffer:
---
---   1. `lib.nvim.notify`'s own delivery pipeline (`notify.popup.M.deliver`)
---      pushes every toast/history entry directly, at the source -- not
---      through the `ui_attach` logger below. A real-TUI spike found that
---      routing notify traffic through the logger instead loses vim.notify
---      (when noice owns it) and lib.nvim.notify toasts entirely (neither
---      ever reaches `ext_messages` as a `msg_show` event); writing straight
---      into the store at the point of delivery is the only path that sees
---      everything.
---   2. `vim.ui_attach(ns, {ext_messages=true}, cb)` -- every other message
---      Neovim shows (`:messages`, `:write`, search counts, Lua errors, raw
---      `nvim_echo`, ...). Only `history=true` `msg_show` events are kept by
---      default (`config.kinds` opts a `history=false` kind in explicitly);
---      `replace_last=true` events overwrite the previous entry instead of
---      appending (Neovim's own signal for "this updates the prior line",
---      e.g. a search count after the pattern echo, the second half of a
---      `:write` message) -- skipping that would double every search/write
---      in the popup.
---
--- **Attach policy** (real-TUI spike, `ext-messages-tui-spike-2026-10-01.md`):
--- attaching as the *only* `ext_messages` listener takes over message AND
--- cmdline rendering from the TUI entirely -- nothing gets drawn, not just
--- "nothing recorded". This module therefore only attaches while a renderer
--- is already active (noice loaded, or an explicit override) and detaches
--- the moment that stops being true -- call `M.notify_renderer_changed()`
--- after toggling noice (it fires no enable/disable event of its own, so
--- nothing else can tell); `M.wrap_noice()` is an opt-in convenience that
--- patches `require("noice").enable/disable` to call it automatically.
--- With no renderer this module simply doesn't attach -- `M.push()` (feed 1
--- above) keeps working regardless, only the `ui_attach` feed is gated.
---
--- Entries carry `time_ms` from `vim.uv.hrtime() / 1e6` (monotonic,
--- sub-millisecond) -- `snapshot()`'s `since_ms`/`until_ms` are the same
--- clock, not wall-clock/epoch time. "Last 10 seconds" only ever needs a
--- relative comparison, so a monotonic clock sidesteps DST/epoch-rollover
--- entirely (the trade-off: entries don't survive a Neovim restart, which
--- this module never claimed to support -- it is a ring buffer, not a log
--- file).

require("lib.nvim.messages.@types")

local fast_event = require("lib.nvim.notify.internal.fast_event")

local M = {}

---@type Lib.Messages.Config
local DEFAULTS = {
  ring_size = 1000,
  kinds = {},
  renderer_override = nil,
}

---@type Lib.Messages.Config
local config = vim.deepcopy(DEFAULTS)

---@type Lib.Messages.Entry[]
local entries = {}

---@type integer
local head = 1

---@type integer
local count = 0

---@type fun(entry: Lib.Messages.Entry)[]
local listeners = {}

-- `kind` -> `vim.log.levels` value, for `msg_show` events (Neovim gives no
-- level of its own). Verified against a real TUI, not guessed from docs --
-- see the spike's "Kind-Katalog". Anything absent here defaults to INFO.
local KIND_LEVEL = {
  lua_error = vim.log.levels.ERROR,
  echoerr = vim.log.levels.ERROR,
}

-- `kind`s Neovim itself marks `history=true` for -- kept by default without
-- needing `config.kinds` to list them. Anything NOT in this table is only
-- kept when `history=true` is seen on the actual event (most kinds already
-- are) or when `config.kinds` opts it in explicitly (a `history=false` kind
-- like `list_cmd`/`echo`/`search_cmd`).
local ns = nil ---@type integer|nil
local attached = false

---@internal
---@return boolean
local function has_renderer()
  if config.renderer_override ~= nil then
    return config.renderer_override
  end
  if package.loaded["noice"] == nil then
    return false
  end
  -- `package.loaded["noice"]` stays non-nil for the rest of the session once
  -- noice has been required, even after `:Noice disable` -- that only flips
  -- noice's own `Config._running` flag. Checking module-loaded state alone
  -- would mean this module never detaches again once noice has loaded once.
  local ok, noice_config = pcall(require, "noice.config")
  return ok and noice_config.is_running() == true
end

---@internal
---Append `entry` into the ring (a true circular buffer: `head`/`count`
---index into a fixed-size `entries`, so both append and eviction are O(1)
---instead of shifting the whole array on every push once the ring is
---full). Notifies listeners after the entry is actually stored, over a
---snapshot of `listeners` -- a listener unsubscribing itself or another
---mid-dispatch (e.g. a "fire once" pattern via `off_message`) must not
---perturb the in-progress iteration and silently skip a later listener.
---@param entry Lib.Messages.Entry
local function store(entry)
  local ring_size = config.ring_size
  if entry.replace_last and count > 0 then
    entries[(head + count - 2) % ring_size + 1] = entry
  else
    if count < ring_size then
      count = count + 1
      entries[(head + count - 2) % ring_size + 1] = entry
    else
      entries[head] = entry
      head = head % ring_size + 1
    end
  end
  local snapshot = vim.list_extend({}, listeners)
  for _, fn in ipairs(snapshot) do
    local ok, err = pcall(fn, entry)
    if not ok then
      vim.schedule(function()
        vim.notify(("[lib.nvim.messages] a listener errored: %s"):format(err), vim.log.levels.WARN)
      end)
    end
  end
end

---@internal
---Whether `history`/`kind` should be kept by the ui_attach feed.
---@param kind string
---@param history boolean
---@return boolean
local function should_keep(kind, history)
  if history then
    return true
  end
  return config.kinds[kind] == true
end

---@internal
local function on_ui_event(event, kind, content, replace_last, history)
  if event ~= "msg_show" then
    return
  end
  if not should_keep(kind, history == true) then
    return
  end
  local text = {}
  for _, chunk in ipairs(content or {}) do
    text[#text + 1] = chunk[2]
  end
  store({
    time_ms = vim.uv.hrtime() / 1e6,
    level = KIND_LEVEL[kind] or vim.log.levels.INFO,
    kind = kind,
    content = table.concat(text),
    source = nil,
    replace_last = replace_last == true,
  })
end

---@internal
---Whether any floating window is currently open. `vim.ui_attach` is
---documented (`notify/popup.lua`'s own finding) to hang indefinitely --
---never returning -- if called while one is already open; `pcall` cannot
---protect against a call that never comes back, only against one that
---errors. `maybe_attach` below must check this itself before attaching.
---@return boolean
local function any_float_open()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local ok, cfg = pcall(vim.api.nvim_win_get_config, w)
    if ok and cfg.relative ~= "" then
      return true
    end
  end
  return false
end

---@type fun()
local maybe_attach

---@internal
---One-shot retry: try `maybe_attach` again the moment any window closes,
---since that is the only signal that a previously-open float might now be
---gone. Re-arming on every `WinClosed` (not just once overall) is cheap and
---correct even if several floats are stacked.
local function schedule_attach_retry()
  local group = vim.api.nvim_create_augroup("LibNvimMessagesAttachRetry", { clear = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    once = true,
    callback = function()
      maybe_attach()
    end,
  })
end

---Attach the `ext_messages` logger if a renderer exists and it isn't
---already attached. Deferred (past the current fast-event tick) and
---skipped entirely while any floating window is open, retrying once one
---closes -- see `any_float_open`'s doc comment for why `pcall` alone can't
---guard this.
maybe_attach = function()
  if attached or not has_renderer() then
    return
  end
  vim.schedule(function()
    if attached or not has_renderer() then
      return
    end
    if any_float_open() then
      schedule_attach_retry()
      return
    end
    ns = ns or vim.api.nvim_create_namespace("lib_nvim_messages")
    local ok = pcall(vim.ui_attach, ns, { ext_messages = true }, on_ui_event)
    attached = ok
  end)
end

---@internal
---Detach the moment no renderer is left -- the logger must never become the
---sole `ext_messages` listener (it would take over message AND cmdline
---rendering from the TUI with nothing to draw either).
local function maybe_detach()
  if not attached then
    return
  end
  pcall(vim.ui_detach, ns)
  attached = false
end

---Change module-wide defaults. Safe to call more than once (e.g. a config
---reload) -- resets to `DEFAULTS` merged with `opts`, not an accumulation.
---A `ring_size` change resets the ring itself: the circular buffer's
---indices are only valid for the size they were written under.
---@param opts? Lib.Messages.Config
---@return nil
function M.setup(opts)
  local new_config = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), opts or {})
  new_config.ring_size = math.max(1, new_config.ring_size)
  if new_config.ring_size ~= config.ring_size then
    entries = {}
    head = 1
    count = 0
  end
  config = new_config
  M.notify_renderer_changed()
end

---Re-evaluate the attach policy -- call after toggling whatever renderer
---`has_renderer()` depends on (e.g. `:Noice enable`/`disable`, which fires
---no event of its own to detect this any other way).
---@return nil
function M.notify_renderer_changed()
  if has_renderer() then
    maybe_attach()
  else
    maybe_detach()
  end
end

---Opt-in convenience: patches `require("noice").enable`/`disable` to call
---`notify_renderer_changed()` automatically. pcall-guarded, a no-op when
---noice isn't installed. Call once, e.g. from setup.
---@return nil
function M.wrap_noice()
  local ok, noice = pcall(require, "noice")
  if not ok or type(noice) ~= "table" then
    return
  end
  for _, name in ipairs({ "enable", "disable" }) do
    local orig = noice[name]
    if type(orig) == "function" then
      noice[name] = function(...)
        local results = { orig(...) }
        M.notify_renderer_changed()
        return unpack(results)
      end
    end
  end
end

---Low-level append, bypassing the `ext_messages` feed entirely. Used by
---`lib.nvim.notify`'s delivery pipeline so notify/toast traffic is never
---lost to the attach policy above (see the module doc).
---@param entry Lib.Messages.PushEntry
---@return nil
M.push = fast_event.guard(function(entry)
  store({
    time_ms = entry.time_ms or (vim.uv.hrtime() / 1e6),
    level = entry.level or vim.log.levels.INFO,
    kind = entry.kind or "notify",
    content = entry.content or "",
    source = entry.source,
    replace_last = entry.replace_last == true,
  })
end)

---Entries in `[since_ms, until_ms]` (both ends optional), oldest first,
---optionally narrowed to `kinds`/`levels` allow-lists. A plain copy -- the
---caller can't mutate the internal ring through it.
---@param opts? Lib.Messages.SnapshotOpts
---@return Lib.Messages.Entry[]
function M.snapshot(opts)
  opts = opts or {}
  local kinds_filter = opts.kinds and {} or nil
  if kinds_filter then
    for _, k in ipairs(opts.kinds) do
      kinds_filter[k] = true
    end
  end
  local levels_filter = opts.levels and {} or nil
  if levels_filter then
    for _, l in ipairs(opts.levels) do
      levels_filter[l] = true
    end
  end

  local out = {}
  for i = 0, count - 1 do
    local entry = entries[(head + i - 1) % config.ring_size + 1]
    local in_range = (not opts.since_ms or entry.time_ms >= opts.since_ms)
      and (not opts.until_ms or entry.time_ms <= opts.until_ms)
    local kind_ok = not kinds_filter or kinds_filter[entry.kind]
    local level_ok = not levels_filter or levels_filter[entry.level]
    if in_range and kind_ok and level_ok then
      out[#out + 1] = vim.deepcopy(entry)
    end
  end
  return out
end

---Subscribe to every entry stored from now on (both feeds). Returns `fn`
---itself, usable as the `off_message` handle.
---@param fn fun(entry: Lib.Messages.Entry)
---@return fun(entry: Lib.Messages.Entry)
function M.on_message(fn)
  listeners[#listeners + 1] = fn
  return fn
end

---Unsubscribe a handle returned by `on_message`.
---@param fn fun(entry: Lib.Messages.Entry)
---@return nil
function M.off_message(fn)
  for i, listener in ipairs(listeners) do
    if listener == fn then
      table.remove(listeners, i)
      return
    end
  end
end

---@type Lib.Messages
return M
