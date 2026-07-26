-- docs/EXAMPLES/kit-toast.lua
--
-- Module:   lib.nvim.ui.kit.toast (lib.nvim.ui.kit.toast)
-- Scenario: an ephemeral, non-focus-stealing message in the top-right
--           corner that auto-dismisses -- for background-job feedback
--           ("build finished", "sync done") where stealing the cursor or
--           blocking on a keypress would be actively annoying.

local kit = require("lib.nvim.ui.kit")

-- A single toast, default 3s auto-dismiss:
kit.toast({ message = "background job done" })

-- Multiple toasts stack downward automatically -- fire a few in a row and
-- watch them queue instead of overlapping:
kit.toast({ title = "Sync", message = "repo A up to date" })
kit.toast({ title = "Sync", message = "repo B up to date" })
kit.toast({ title = "Sync", message = "repo C up to date", timeout = 5000 })

-- Query/clear the toast module directly (not the `kit.*` front door) when
-- you need to know how many are live, or want to dismiss all of them at
-- once -- e.g. before showing a blocking prompt so nothing overlaps it:
local toast = require("lib.nvim.ui.kit.toast")
vim.notify(("%d toast(s) currently visible"):format(toast.active()))
toast.clear()
