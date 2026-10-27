---@module 'lib.nvim.ui.kit.modal'
--- Which modal kit dialogs are open right now, and a way to be told when none is.
---
--- A dialog that takes the keyboard (confirm, input, select, sheet, ...) registers its surface
--- through `surface.open{ modal = true }`; the registry forgets it when the float closes, for any
--- cause. `kit.ask` uses it to wait for a free moment without looking again every few hundred
--- milliseconds: it subscribes once with `on_free` and is called when the last modal dialog went.
---
--- Nothing here owns a window or a keymap. A float closed without `WinClosed` (never in practice)
--- is dropped from `busy()` as soon as it is looked at, and the subscribers are woken by the next
--- close.

local M = {}

---@type Lib.UI.Kit.Surface[]
local open = {}

---@type (fun())[]
local listeners = {}

--- Forget surfaces whose window is gone.
local function prune()
  for i = #open, 1, -1 do
    if not open[i]:is_valid() then
      table.remove(open, i)
    end
  end
end

--- Wake the subscribers when nothing is open. Each is called once, in the order it subscribed, on
--- the next loop iteration (a close runs inside `WinClosed`, where opening a float is restricted).
local function wake()
  prune()
  if #open > 0 or #listeners == 0 then
    return
  end
  local due = listeners
  listeners = {}
  vim.schedule(function()
    for _, fn in ipairs(due) do
      local ok, err = pcall(fn)
      if not ok then
        vim.notify(
          "lib.nvim.ui.kit.modal: a waiting caller failed: " .. tostring(err),
          vim.log.levels.ERROR
        )
      end
    end
  end)
end

--- Register a surface as an open modal dialog. Idempotent per surface.
---@param surf Lib.UI.Kit.Surface
function M.enter(surf)
  for _, s in ipairs(open) do
    if s == surf then
      return
    end
  end
  open[#open + 1] = surf
  surf:on_close(function()
    for i, s in ipairs(open) do
      if s == surf then
        table.remove(open, i)
        break
      end
    end
    wake()
  end)
end

--- Whether a modal dialog is open.
---@return boolean
function M.busy()
  prune()
  return #open > 0
end

--- Call `fn` once, after the next moment no modal dialog is open (not before the current call
--- has returned: an `fn` registered while nothing is open is called on the next loop iteration).
--- Returns a function that withdraws it.
---@param fn fun()
---@return fun() cancel
function M.on_free(fn)
  listeners[#listeners + 1] = fn
  if #open == 0 then
    wake()
  end
  return function()
    for i, f in ipairs(listeners) do
      if f == fn then
        table.remove(listeners, i)
        return
      end
    end
  end
end

return M
