-- docs/EXAMPLES/kit-note.lua
--
-- Module:   lib.nvim.ui.kit.note (lib.nvim.ui.kit.note)
-- Scenario: a centered title + message float, auto-closable with q/<Esc>,
--           optionally auto-dismissing after a timeout -- the simplest kit
--           component, useful for "here's what just happened" feedback
--           that a plain vim.notify() would scroll past too quickly.

local kit = require("lib.nvim.ui.kit")

-- Direct call:
kit.note({
  title = "Saved",
  message = "Wrote 3 files",
  timeout = 2000, -- ms; omit to require an explicit q/<Esc> to close
})

-- Same thing through the generic dispatch front door -- useful when the
-- popup "type" is itself a variable (e.g. picked by a caller's config):
kit.popup({ type = "note", title = "Saved", message = "Wrote 3 files" })

-- A multi-line message (either a "\n"-joined string or a string[] both
-- work) plus a non-default theme preset for this one call only:
kit.note({
  title = "Build failed",
  message = { "3 errors:", " - foo.lua:12", " - bar.lua:4", " - baz.lua:88" },
  theme = "solid",
})

-- The handle returned by note.open()/kit.note() is a `Surface` -- the same
-- lifecycle handle every kit component builds on, in case you want to
-- close it programmatically instead of waiting for q/<Esc>/timeout:
local surf = kit.note({ title = "Working...", message = "This will self-close" })
vim.defer_fn(function()
  if surf then
    surf:close()
  end
end, 500)
