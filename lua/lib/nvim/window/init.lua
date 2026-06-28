---@module 'lib.nvim.window'
---Window-control helpers for overlay / floating windows.
---
---Two ways to consume this namespace:
---
---  -- 1) Free functions (recommended in plugin code; tree-shake friendly):
---  local window = require("lib.nvim.window")
---  window.nice_quit(winid)
---  window.set_title(winid, "New Title")
---
---  -- 2) Constructor — a thin wrapper bound to one window id:
---  local w = require("lib.nvim.window").attach(winid)
---  w.nice_quit()
---  w.set_title("New Title")
---
---The constructor is pure sugar: every method delegates to the matching free
---function with `winid` pre-applied. The free functions stay the single source
---of truth, so they remain independently testable.

require("lib.nvim.window.@types")

local M = {}

M.nice_quit = require("lib.nvim.window.nice_quit")
M.set_title = require("lib.nvim.window.set_title")
M.make_scratch = require("lib.nvim.window.make_scratch")
M.close_on_focus_lost = require("lib.nvim.window.close_on_focus_lost")
M.center = require("lib.nvim.window.center")

---Construct a fluent wrapper bound to a single window id.
---Methods are called with **dot syntax** (`w.nice_quit()`), not colon syntax:
---the bound `winid` is captured in a closure, so there is no implicit `self`.
---@param winid integer
---@return Lib.Window.Handle
function M.attach(winid)
  return setmetatable({ winid = winid }, {
    __index = function(tbl, key)
      local fn = M[key]
      if type(fn) ~= "function" then
        return nil
      end
      local bound = rawget(tbl, "winid")
      return function(...)
        return fn(bound, ...)
      end
    end,
  })
end

---@type Lib.Window
return M
