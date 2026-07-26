---@module 'lib.nvim.ui.kit.viewer'
--- Viewer component: a read-only, centered info panel — auto-sized to its
--- content, `q`/`<Esc>` closes, and (unlike `note`) closes as soon as focus
--- leaves it. This is the "show some info, dismiss it" float that got
--- hand-rolled independently across consumer plugins: buffer creation,
--- width/height computed from content, centering, `border = rounded`,
--- `q`/`<Esc>` keymap, close-on-WinLeave — six separate times in
--- filetree.nvim alone (node info, cheatsheet, marks, trash history, ...),
--- plus learn-cli.nvim and the nvim-config's own LSP info command.
---
--- Distinct from `note`: `note` is a passive, non-focused notification
--- (`enter = false`, no focus-loss auto-close, optional timeout); `viewer`
--- is meant to be read and possibly scrolled (`enter = true`), and dismisses
--- itself the moment the user's attention moves elsewhere — no timeout,
--- because there's no way to know how long a piece of info takes to read.

local surface = require("lib.nvim.ui.kit.surface")
local close_on_focus_lost = require("lib.nvim.window.close_on_focus_lost")

local M = {}

---Normalize a message (string or string[]) to buffer lines.
---@param message string|string[]
---@return string[]
local function to_lines(message)
  if type(message) == "table" then
    return message
  end
  if type(message) ~= "string" then
    return { tostring(message) }
  end
  return vim.split(message, "\n", { plain = true })
end

---Open a read-only info panel.
---@param opts Lib.UI.Kit.ViewerOpts
---@return Lib.UI.Kit.Surface|nil
function M.open(opts)
  opts = opts or {}

  local surf = surface.open({
    lines = to_lines(opts.lines or opts.message or ""),
    theme = opts.theme,
    title = opts.title,
    width = opts.width,
    height = opts.height,
    relative = opts.relative or "editor",
    nice_quit = true,
    enter = opts.enter ~= false,
    filetype = opts.filetype or "lib-kit-viewer",
    modifiable = false,
  })

  if not surf then
    return nil
  end

  -- Dismiss as soon as the user's attention moves elsewhere. Opt-out via
  -- `close_on_focus_lost = false` for a caller that wants the panel to stay
  -- open regardless (e.g. anchored beside a terminal the user keeps typing
  -- into) and rely on q/<Esc> alone.
  if opts.close_on_focus_lost ~= false then
    close_on_focus_lost(surf.winid)
  end

  return surf
end

return M
