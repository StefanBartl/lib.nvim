---@module 'lib.nvim.notify.safe'
---@description Safe notification utilities for calling vim.notify from fast event contexts.
---
--- Provides helpers using vim.schedule, vim.defer_fn and vim.schedule_wrap to avoid
--- calling vim.notify directly from contexts where it might cause issues (e.g., during
--- TextChanged, CursorMoved, or other high-frequency events).
-- FIX: Anchließenden text auf englisch pbersetzten
--[[
lib.nvim.notify.safe

Dieses Modul stellt sichere Wrapper um `vim.notify` bereit, die speziell für
Fast-Event-Kontexte in Neovim gedacht sind.

Problem:
`vim.notify` darf nicht zuverlässig aus allen Kontexten direkt aufgerufen werden.
In Autocommands, LSP-Callbacks oder anderen hochfrequenten Events kann dies zu
Fehlern, UI-Problemen oder undefiniertem Verhalten führen.

Lösung:
Dieses Modul kapselt bewährte Neovim-Mechanismen (`vim.schedule`, `vim.defer_fn`,
`vim.schedule_wrap`) hinter einer konsistenten API und stellt mehrere Strategien
bereit:

- schedule:
  Plant die Benachrichtigung sofort im nächsten Main-Loop-Tick ein.
  Empfohlener Standardfall.

- defer:
  Verzögert die Benachrichtigung um eine definierte Zeitspanne.
  Geeignet für UI-Übergänge oder Debouncing.

- wrap:
  Liefert eine bereits geschedulte Funktion für wiederholte, effiziente Aufrufe.

Zusätzlich bietet `create_safe(prefix)` eine sichere Variante von
`lib.nvim.notify.create`, die automatisch Prefixing und Scheduling kombiniert.

Ziel:
- keine direkten `vim.notify`-Aufrufe aus unsicheren Kontexten
- klare, wiederverwendbare API
- identisches Nutzungsgefühl wie bei normalen Notifiern
]]--

local M = {}

--- Safe notify using vim.schedule: schedules the notify on the main loop immediately.
--- Use this as the default safe method when you need to notify from a fast context.
---
---@param msg string Message to display
---@param level? integer vim.log.levels value (defaults to INFO)
---@param opts? table Additional notify options (e.g., {timeout = 3000})
---@return nil
function M.schedule(msg, level, opts)
  level = level or vim.log.levels.INFO
  opts = opts or {}

  vim.schedule(function()
    vim.notify(msg, level, opts)
  end)
end

--- Safe notify using vim.defer_fn: defers execution by delay_ms milliseconds.
--- Useful when you want a small delay before showing the notification.
---
---@param msg string Message to display
---@param level? integer vim.log.levels value (defaults to INFO)
---@param opts? table Additional notify options
---@param delay_ms? integer Delay in milliseconds (defaults to 0)
---@return nil
function M.defer(msg, level, opts, delay_ms)
  level = level or vim.log.levels.INFO
  opts = opts or {}
  local dt = tonumber(delay_ms) or 0

  vim.defer_fn(function()
    vim.notify(msg, level, opts)
  end, dt)
end

--- Create a scheduled notifier function for repeated safe calls.
--- Returns a function that is already wrapped with vim.schedule_wrap.
--- This is the most efficient option when you need to notify repeatedly from fast contexts.
---
---@return fun(msg: string, level?: integer, opts?: table)
function M.wrap()
  return vim.schedule_wrap(function(msg, level, opts)
    level = level or vim.log.levels.INFO
    opts = opts or {}
    vim.notify(msg, level, opts)
  end)
end

--- Convenience wrapper that chooses scheduling method based on mode parameter.
--- Prevents accidental immediate calls to vim.notify from unsafe contexts.
---
---@param msg string Message to display
---@param level? integer vim.log.levels value (defaults to INFO)
---@param opts? table Additional notify options
---@param mode? '"schedule"'|'"defer"'|'"wrap"' Scheduling mode (defaults to "schedule")
---@param delay_ms? integer Delay for "defer" mode (defaults to 0)
---@return nil
function M.notify(msg, level, opts, mode, delay_ms)
  mode = mode or "schedule"
  level = level or vim.log.levels.INFO
  opts = opts or {}

  if mode == "defer" then
    M.defer(msg, level, opts, delay_ms)
  elseif mode == "wrap" then
    local wrapped = M.wrap()
    wrapped(msg, level, opts)
  else
    M.schedule(msg, level, opts)
  end
end

--- Create a safe notifier with prefix support (integrates with lib.nvim.notify.create).
--- Returns a table with safe methods that automatically prefix messages.
---
---@param prefix string Notification prefix (e.g., "[plugin-name]")
---@return table notifier Safe notifier with info/warn/error/debug/notify methods
function M.create_safe(prefix)
  -- Normalize prefix once
  if type(prefix) ~= "string" then
    prefix = ""
  end

  if prefix ~= "" and not prefix:match("%s$") then
    prefix = prefix .. " "
  end

  local notifier = {}

  ---@param msg string
  ---@param level? integer
  ---@param opts? table
  function notifier.notify(msg, level, opts)
    if type(msg) ~= "string" then
      msg = tostring(msg)
    end
    level = level or vim.log.levels.INFO
    opts = opts or {}

    M.schedule(prefix .. msg, level, opts)
  end

  ---@param msg string
  ---@param opts? table
  function notifier.info(msg, opts)
    notifier.notify(msg, vim.log.levels.INFO, opts)
  end

  ---@param msg string
  ---@param opts? table
  function notifier.warn(msg, opts)
    notifier.notify(msg, vim.log.levels.WARN, opts)
  end

  ---@param msg string
  ---@param opts? table
  function notifier.error(msg, opts)
    notifier.notify(msg, vim.log.levels.ERROR, opts)
  end

  ---@param msg string
  ---@param opts? table
  function notifier.debug(msg, opts)
    notifier.notify(msg, vim.log.levels.DEBUG, opts)
  end

  ---@type Lib.Notify.Safe.Notifier
  return notifier
end

---@type Lib.Notify.Safe
return M
