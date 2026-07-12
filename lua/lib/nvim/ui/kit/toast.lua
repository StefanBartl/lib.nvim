---@module 'lib.nvim.ui.kit.toast'
--- Toast component: an ephemeral, non-focus-stealing message in the top-right
--- corner that auto-dismisses. Toasts stack downward.
---
--- This submodule owns a small internal registry of the currently visible
--- toasts (needed to stack them). That state is confined here and exposed only
--- through `active()` — no shared global window state (see UI-KIT-CONCEPT §14.3).

local surface = require("lib.nvim.ui.kit.surface")

local api = vim.api

local M = {}

local DEFAULT_TIMEOUT = 3000
local WIDTH = 40
local MARGIN = 2 -- columns from the right edge / rows from the top

--- Live toasts, oldest first. Each: { surf = Surface, height = integer }.
local stack = {}

--- Drop dead toasts and reflow the survivors from the top-right corner down.
local function reflow()
  local live = {}
  for _, t in ipairs(stack) do
    if t.surf:is_valid() then
      live[#live + 1] = t
    end
  end
  stack = live

  local row = MARGIN - 1
  local col = math.max(0, vim.o.columns - WIDTH - MARGIN)
  for _, t in ipairs(stack) do
    pcall(api.nvim_win_set_config, t.surf.winid, {
      relative = "editor",
      row = row,
      col = col,
      width = WIDTH,
      height = t.height,
    })
    row = row + t.height + 1
  end
end

--- Show a toast.
---@param opts table  # { message, title?, theme?, timeout? }
---@return Lib.UI.Kit.Surface|nil
function M.open(opts)
  opts = opts or {}
  local message = opts.message or ""
  local lines = type(message) == "table" and message
    or vim.split(tostring(message), "\n", { plain = true })

  local surf = surface.open({
    lines = lines,
    theme = opts.theme,
    title = opts.title,
    width = WIDTH,
    height = #lines,
    relative = "editor",
    row = 0,
    col = 0,
    enter = false, -- never steal focus
    focusable = false,
  })
  if not surf then
    return nil
  end

  local entry = { surf = surf, height = #lines }
  stack[#stack + 1] = entry
  reflow()

  surf:on_close(reflow)

  local timeout = tonumber(opts.timeout) or DEFAULT_TIMEOUT
  if timeout > 0 then
    vim.defer_fn(function()
      surf:close()
    end, timeout)
  end

  return surf
end

--- Number of live toasts (also prunes dead ones).
---@return integer
function M.active()
  reflow()
  return #stack
end

--- Close every visible toast.
function M.clear()
  for _, t in ipairs(stack) do
    t.surf:close()
  end
  reflow()
end

return M
