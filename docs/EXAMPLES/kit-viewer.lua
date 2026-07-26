-- docs/EXAMPLES/kit-viewer.lua
--
-- Module:   lib.nvim.ui.kit.viewer (lib.nvim.ui.kit.viewer)
-- Scenario: a read-only info panel — auto-sized to its content, dismissed
--           with q/<Esc> OR automatically the moment focus leaves it. This
--           is the "show some info, then get out of the way" float that
--           kept getting hand-rolled independently across plugins: node
--           info, a cheatsheet, marks, undo history, LSP info — each one
--           re-implementing "create a buffer, size it from content, center
--           it, border=rounded, q/Esc to close, close on WinLeave".

local kit = require("lib.nvim.ui.kit")

-- Simple case: title + a few lines, closes itself the moment you move to
-- another window (unlike kit.note, which stays open until q/<Esc>/timeout).
kit.viewer({
  title = "Node Info",
  lines = {
    "name:     foo.lua",
    "size:     128 bytes",
    "modified: 2026-07-26 14:03",
  },
})

-- A cheatsheet-style panel: longer content, still auto-sized (clamped to
-- the editor, per lib.nvim.window.make_scratch's own defaults).
kit.viewer({
  title = "Keymaps",
  lines = {
    "j/k       move down/up",
    "<CR>      open under cursor",
    "d         delete",
    "r         rename",
    "q/<Esc>   close this panel",
  },
})

-- Pass a single string instead of a line array -- split on "\n" for you,
-- same as kit.note.
kit.viewer({ title = "Status", message = "3 files changed\n12 insertions\n4 deletions" })

-- Opt out of the focus-loss auto-close when the panel should stay open
-- regardless of where the user's attention goes (e.g. anchored beside a
-- terminal the user keeps typing into) -- q/<Esc> still closes it.
kit.viewer({
  title = "Build Log",
  lines = { "Compiling...", "Linking...", "Done." },
  close_on_focus_lost = false,
})

-- The handle is the same Surface every kit component returns, so it can be
-- driven programmatically too (e.g. refreshing content on a timer):
local v = kit.viewer({ title = "Live Status", lines = { "waiting..." } })
if v then
  vim.defer_fn(function()
    if v:is_valid() then
      v:set_lines({ "done!" })
    end
  end, 1000)
end
