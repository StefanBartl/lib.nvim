---@module 'lib.nvim.window.nice_quit'
---Make an overlay / floating window closable with `q` or `<Esc>` in Normal mode.
---
---Intended for non-file windows (hover, pickers, debug panels, …). The keymaps
---are **buffer-local** and bound to **Normal mode only**. Mapping `<Esc>` in
---Normal mode (and not Insert/Terminal mode) yields the natural "double Escape"
---feel for free: the first `<Esc>` leaves Insert/Terminal mode (Vim default),
---the second `<Esc>` — now in Normal mode — closes the window.

require("lib.nvim.window.@types")

local api = vim.api
local notify = require("lib.nvim.notify").create("[lib.nvim.window.nice_quit]")

---Normal-mode keys that close the window when no override is given.
local DEFAULT_KEYS = { "q", "<Esc>" }

---Resolve the buffer backing a window, or nil if the window is invalid.
---@param winid integer
---@return integer|nil bufnr
local function win_buf(winid)
  if not api.nvim_win_is_valid(winid) then
    return nil
  end
  local ok, bufnr = pcall(api.nvim_win_get_buf, winid)
  if not ok then
    return nil
  end
  return bufnr
end

---Close `winid` safely. Idempotent (no-op if already gone) and never closes the
---last remaining window in the tabpage, which Neovim would refuse anyway.
---@param winid integer
---@param force boolean discard unsaved changes when true
---@return boolean closed true when this call closed the window
local function safe_close(winid, force)
  if not api.nvim_win_is_valid(winid) then
    return false
  end
  if #api.nvim_tabpage_list_wins(0) <= 1 then
    notify.debug("refusing to close the last window in the tabpage")
    return false
  end
  return pcall(api.nvim_win_close, winid, force) == true
end

---Bind `q` / `<Esc>` (Normal mode, buffer-local) to close `winid`.
---@param winid integer
---@param opts? Lib.Window.NiceQuitOpts
---@return boolean ok true when the keymaps were attached
local function nice_quit(winid, opts)
  opts = opts or {}

  local bufnr = win_buf(winid)
  if not bufnr then
    notify.debug(string.format("invalid window id: %s", tostring(winid)))
    return false
  end

  local keys = opts.keys or DEFAULT_KEYS
  local force = opts.force == true

  for _, lhs in ipairs(keys) do
    vim.keymap.set("n", lhs, function()
      safe_close(winid, force)
    end, {
      buffer = bufnr,
      -- nowait: fire immediately so `<Esc>` / `q` are not delayed by longer mappings.
      nowait = true,
      silent = true,
      desc = "lib.nvim: close window",
    })
  end

  return true
end

return nice_quit
