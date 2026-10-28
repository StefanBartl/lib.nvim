---@module 'lib.nvim.ui.kit.hook'
--- A hook in front of the modal dialogs of the kit (`confirm`, `ask`, `input`, `select`, `form`,
--- `sheet`), so a test can answer them without a window. Without a hook it costs a table access.
---
---   kit.set_dialog_hook(function(kind, opts)
---     -- `kind` names the component, `opts` are the caller's options as they came in
---     return true, value   -- handled: nothing opens, the caller's callback gets `value`
---   end)                    -- `return false` (or nothing) passes the dialog on to the real one
---
--- `value` is what the user would have said, in the terms of the component: `confirm`/`ask` an index
--- or a label of `choices` (a plain question: `true`/`false`, or 1 yes / 2 no), `input` the text,
--- `select` an index or an item, `form`/`sheet` the keyed table of values. `nil` is a dismissal. The
--- answer is delivered on the next loop turn, as a real one is; the call itself returns a stand-in
--- surface that is already closed, so a caller that checks the surface for "did it open" sees one.
---
--- An error the hook raises is raised in the caller: a test hook that has no answer says so loudly.

local M = {}

---@alias Lib.UI.Kit.DialogHook fun(kind: string, opts: table): boolean|nil, any

---@type Lib.UI.Kit.DialogHook|nil
local current

--- Set the hook (`nil` removes it).
---@param fn Lib.UI.Kit.DialogHook|nil
function M.set(fn)
  assert(fn == nil or type(fn) == "function", "kit.set_dialog_hook: a function or nil")
  current = fn
end

---@return Lib.UI.Kit.DialogHook|nil
function M.get()
  return current
end

--- What a hooked call returns in place of a surface: closed, every method a no-op.
---@return table
local function stand_in()
  return {
    hooked = true,
    close = function() end,
    is_open = function()
      return false
    end,
  }
end

--- Offer the dialog to the hook. When it answers, `deliver(value)` runs on the next loop turn and
--- the stand-in surface is returned; otherwise `nil` and the caller opens the real dialog.
---@param kind "confirm"|"ask"|"input"|"select"|"form"|"sheet"
---@param opts table
---@param deliver fun(value: any)
---@return table|nil surface
function M.intercept(kind, opts, deliver)
  local fn = current
  if fn == nil then
    return nil
  end
  local handled, value = fn(kind, opts)
  if not handled then
    return nil
  end
  vim.schedule(function()
    deliver(value)
  end)
  return stand_in()
end

return M
