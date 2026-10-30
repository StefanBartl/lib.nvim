---@module 'lib.nvim.ui.kit.sidebar_state'
--- The one place `lib.nvim.ui.kit.sidebar` keeps its handles (UI-51): which sidebars exist
--- (open or hidden) and which one displaced which (UI-54). Read and written only through the
--- functions below; `kit.sidebar` holds no handle in a module local of its own.
---
--- A window is found again through its buffer variable (`kit.sidebar.find`), not through
--- this list (UI-31); the list is what `close_all` walks and what exclusivity asks.

local api = vim.api

local M = {}

---@type Lib.UI.Kit.Sidebar[]
local handles = {}

--- handle -> the handle it displaced when it took its slot.
---@type table<Lib.UI.Kit.Sidebar, Lib.UI.Kit.Sidebar>
local displaced = {}

--- Remember a new handle.
---@param handle Lib.UI.Kit.Sidebar
function M.add(handle)
  handles[#handles + 1] = handle
end

--- Forget `handle`. A sidebar that had displaced it now stands for what `handle` itself had
--- displaced, so a chain A <- B <- C with B closed while hidden still brings A back when C closes.
---@param handle Lib.UI.Kit.Sidebar
function M.remove(handle)
  for i = #handles, 1, -1 do
    if handles[i] == handle then
      table.remove(handles, i)
    end
  end
  local inherited = displaced[handle]
  displaced[handle] = nil
  for other, target in pairs(displaced) do
    if target == handle then
      displaced[other] = inherited
    end
  end
end

--- Every known handle, oldest first (a copy: closing while iterating is safe).
---@return Lib.UI.Kit.Sidebar[]
function M.list()
  return { unpack(handles) }
end

--- The newest handle named `name`, or nil.
---@param name string
---@return Lib.UI.Kit.Sidebar|nil
function M.get(name)
  for i = #handles, 1, -1 do
    if handles[i].name == name then
      return handles[i]
    end
  end
  return nil
end

--- The sidebar visible at `position` in tabpage `tab`, other than `except`.
---@param tab integer
---@param position string
---@param except? Lib.UI.Kit.Sidebar
---@return Lib.UI.Kit.Sidebar|nil
function M.visible_at(tab, position, except)
  for i = #handles, 1, -1 do
    local h = handles[i]
    if h ~= except and h.position == position and h:is_visible() then
      if api.nvim_win_get_tabpage(h.winid) == tab then
        return h
      end
    end
  end
  return nil
end

--- Record that `handle` displaced `other` (nil clears it).
---@param handle Lib.UI.Kit.Sidebar
---@param other Lib.UI.Kit.Sidebar|nil
function M.set_displaced(handle, other)
  displaced[handle] = other
end

--- Take the handle `handle` displaced: returns it and forgets it, so it is restored once.
---@param handle Lib.UI.Kit.Sidebar
---@return Lib.UI.Kit.Sidebar|nil
function M.take_displaced(handle)
  local other = displaced[handle]
  displaced[handle] = nil
  return other
end

--- The handle `handle` displaced, without taking it.
---@param handle Lib.UI.Kit.Sidebar
---@return Lib.UI.Kit.Sidebar|nil
function M.displaced(handle)
  return displaced[handle]
end

return M
