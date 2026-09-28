---@module 'lib.nvim.ui.kit.toast'
--- Toast component: an ephemeral, non-focus-stealing message in the top-right
--- corner that auto-dismisses. Toasts stack downward.
---
--- This submodule owns a small internal registry of the currently visible
--- toasts (needed to stack them). That state is confined here and exposed only
--- through `active()` — no shared global window state.

local surface = require("lib.nvim.ui.kit.surface")
local autocmd = require("lib.nvim.bindings.autocmd")
local theme = require("lib.nvim.ui.kit.theme")

local api = vim.api

local M = {}

local DEFAULT_TIMEOUT = 3000
local WIDTH = 40
local MARGIN = 2 -- columns from the right edge / rows from the top

--- Live toasts, oldest first. Each: { surf = Surface, height = integer, bordered = boolean }.
local stack = {}

---@internal
--- Drop dead toasts and reflow the survivors from the top-right corner down.
---
--- `row` (per `nvim_win_set_config`) is a bordered float's *content* row --
--- the border itself is drawn one row above/below that, outside `height` --
--- so a bordered toast's true on-screen footprint is `height + 2` rows, not
--- `height`. Advancing `row` by only `t.height + 1` (as if every toast were
--- borderless) used to leave the two border rows unaccounted for, so the
--- next toast's top border landed exactly on the previous one's bottom
--- border -- overwriting it instead of leaving a gap below it.
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
    local box_h = t.bordered and (t.height + 2) or t.height
    row = row + box_h + 1
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

  local entry =
    { surf = surf, height = #lines, bordered = theme.resolve(opts.theme).border ~= "none" }
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

-- Same bug class as PERF-92 (`ui.screenkey`, `lib.nvim.ui.kit.{compare,picker,
-- chooser}`): `reflow()` only ran when a toast opened or closed, so a
-- `VimResized` while one was up left it pinned to the corner computed at the
-- editor's PREVIOUS size until the next open/close reflowed it -- and
-- `M.open`'s `timeout = 0` disables the auto-dismiss entirely, so that
-- window is not bounded the way a default 3s toast's is. Registered once at
-- module load, not per-toast: `reflow()` is already idempotent over an empty
-- `stack`, so there is nothing to enable/disable.
autocmd.create("VimResized", reflow, {
  group = autocmd.group("lib_kit_toast_resize", true),
  desc = "lib.nvim.ui.kit.toast: keep the stack pinned to its corner",
})

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
