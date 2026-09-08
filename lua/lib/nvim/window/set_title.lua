---@module 'lib.nvim.window.set_title'
---Set (or clear) the title of a floating window.
---
---Only floating windows carry a title (`config.relative ~= ""`); for any other
---window this is a safe no-op. Pass `nil` as the title to clear it.

require("lib.nvim.window.@types")

local api = vim.api
local notify = require("lib.nvim.notify").create("[lib.nvim.window.set_title]")

---@param winid integer
---@param title string|nil nil clears the title
---@param opts? Lib.Window.SetTitleOpts
---@return boolean ok true when the title was applied
local function set_title(winid, title, opts)
  opts = opts or {}

  if not api.nvim_win_is_valid(winid) then
    notify.debug(string.format("invalid window id: %s", tostring(winid)))
    return false
  end

  local ok, cfg = pcall(api.nvim_win_get_config, winid)
  if not ok or not cfg then
    return false
  end

  -- Titles are only meaningful on floating windows.
  if cfg.relative == nil or cfg.relative == "" then
    notify.debug("set_title: target is not a floating window; ignoring")
    return false
  end

  -- Neovim only stores / renders a title when the float has a border.
  if title ~= nil and (cfg.border == nil or cfg.border == "none") then
    notify.debug("set_title: float has no border; the title will not be visible")
  end

  -- nvim_win_set_config leaves omitted keys unchanged on an existing float,
  -- so a minimal patch is enough (and avoids round-tripping the full config).
  --
  -- Clearing is the exception, and it is why `{ title = nil }` is not what it
  -- reads like: in Lua that IS the omitted key, so the float kept whatever
  -- title it already had and the documented "pass nil to clear" never did
  -- anything. An empty string is what actually removes it.
  local patch
  if title == nil then
    patch = { title = "" }
  elseif opts.pos ~= nil then
    patch = { title = title, title_pos = opts.pos }
  else
    patch = { title = title }
  end

  return pcall(api.nvim_win_set_config, winid, patch) == true
end

return set_title
