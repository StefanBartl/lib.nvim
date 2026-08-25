---@module 'lib.nvim_usrcmds.autocmds'
---@brief The one autocommand this namespace installs, and its augroup.
---@description
--- Split out from `init.lua` so the three binding kinds each have a home --
--- the same shape every plugin in this ecosystem uses, and the reason the
--- stacking bug below was findable at all.

local autocmd = require("lib.nvim.autocmd")
local actions = require("lib.nvim_usrcmds.actions")

local M = {}

---The augroup the helptags hook belongs to.
---
---It used to have none, and `setup()` is called again on every config reload:
---each call added another `User` autocmd for the same three patterns, so a
---`:Lazy sync` after two reloads ran `helptags ALL` three times. At the ~229ms
---that costs with a hundred-plus plugins, that is visible. A named group with
---`clear = true` makes re-registration idempotent by construction.
M.GROUP = "LibNvimUsrCmdsHelptags"

---Regenerate helptags after lazy.nvim actually changed something on disk.
---
---This used to hang on `LazyDone`, which fires on *every* start. `helptags
---ALL` walks every installed plugin's doc/ directory and rewrites its tags
---file unconditionally, and the second run in the same session costs the same
---because nothing about it is incremental. Paying that on every launch buys
---nothing: help files only change when a plugin is installed or updated, and
---those are exactly the events below.
---
---`:Lib helptags` still regenerates on demand, for the case where something
---changed outside lazy's knowledge.
---@return nil
function M.helptags()
  autocmd.create("User", function()
    actions.helptags()
  end, {
    group = autocmd.group(M.GROUP, true),
    pattern = { "LazyInstall", "LazyUpdate", "LazySync" },
    desc = "[lib.nvim_usrcmds] regenerate helptags after lazy.nvim installs/updates plugins",
  })
end

return M
