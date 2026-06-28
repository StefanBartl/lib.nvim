---@module 'lib.nvim.window.close_on_focus_lost'
---Auto-close an overlay window as soon as focus leaves it.
---
---Registers a one-shot, buffer-local autocmd (default `WinLeave` / `BufLeave`)
---that closes `winid` when the user moves away from it — the usual dismiss
---behaviour for hover popups and transient panels. Returns the augroup id so
---callers can cancel it again via `nvim_del_augroup_by_id`.

require("lib.nvim.window.@types")

local api = vim.api
local notify = require("lib.nvim.notify").create("[lib.nvim.window.close_on_focus_lost]")

---Default events that count as "focus left the overlay".
local DEFAULT_EVENTS = { "WinLeave", "BufLeave" }

---@param winid integer
---@param opts? Lib.Window.CloseOnFocusLostOpts
---@return integer|nil augroup id of the autocommand group, or nil on failure
local function close_on_focus_lost(winid, opts)
  opts = opts or {}

  if not api.nvim_win_is_valid(winid) then
    notify.debug(string.format("invalid window id: %s", tostring(winid)))
    return nil
  end

  local ok, bufnr = pcall(api.nvim_win_get_buf, winid)
  if not ok then
    return nil
  end

  local events = opts.events or DEFAULT_EVENTS
  local force = opts.force ~= false

  local augroup = api.nvim_create_augroup(string.format("LibNvimWindowFocusClose_%d", winid), { clear = true })

  api.nvim_create_autocmd(events, {
    group = augroup,
    buffer = bufnr,
    once = true,
    desc = "lib.nvim: close window on focus lost",
    callback = function()
      -- Defer: closing a window from inside its own WinLeave is unsafe.
      vim.schedule(function()
        if api.nvim_win_is_valid(winid) then
          pcall(api.nvim_win_close, winid, force)
        end
      end)
    end,
  })

  return augroup
end

return close_on_focus_lost
