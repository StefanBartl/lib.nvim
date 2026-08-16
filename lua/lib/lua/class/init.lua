---@module 'lib.lua.class'
--- Prototype OOP: `new`/`extend`/`include`, pure Lua (no `vim` API).
---
--- Two modules in this codebase already hand-roll the classic
--- `Name = {}; Name.__index = Name` prototype independently
--- (`lib.lua.memo.lru`, `lib.nvim.ui.kit.surface`) — this generalizes that
--- shape plus adds inheritance (the classic Lua two-level metatable
--- chain) and mixin composition, neither of which existed anywhere in the
--- codebase before.
---
---```lua
--- local class = require("lib.lua.class")
---
--- local Animal = class.new("Animal")
--- function Animal:init(name)
---   self.name = name
--- end
--- function Animal:speak()
---   return self.name .. " makes a sound"
--- end
---
--- local Dog = Animal:extend("Dog")
--- function Dog:speak() -- override
---   return self.name .. " barks"
--- end
---
--- local rex = Animal.new("Rex")
--- rex:speak() --> "Rex makes a sound"
---
--- local fido = Dog.new("Fido") -- init inherited from Animal, unchanged
--- fido:speak() --> "Fido barks"
---```

local M = {}

---@internal
--- Build a fresh class table: `Cls.__index = Cls` for instance method
--- lookup, and — when `parent` is given — `Cls`'s own metatable chains to
--- `parent` (the classic two-level trick: an instance not finding a
--- method on `Cls` falls through to `Cls`, which not finding it directly
--- falls through to `parent`).
---@param name string
---@param parent table|nil
---@return table
local function make_class(name, parent)
  local Cls = { __name = name, __parent = parent }
  Cls.__index = Cls
  if parent then
    setmetatable(Cls, { __index = parent })
  end

  --- Construct a new instance. Calls `init(self, ...)` if defined
  --- (inherited `init` counts too, via the method-lookup chain above).
  ---@param ... any Forwarded to `init`
  ---@return table instance
  function Cls.new(...)
    local instance = setmetatable({}, Cls)
    if instance.init then
      instance:init(...)
    end
    return instance
  end

  --- Create a subclass: a new class whose method lookup falls back to
  --- this one.
  ---@param sub_name string
  ---@return table
  function Cls:extend(sub_name)
    return make_class(sub_name, self)
  end

  return Cls
end

--- Define a new root class.
---@param name string
---@return table
function M.new(name)
  return make_class(name, nil)
end

--- Copy every function field from `mixin` onto `target`, skipping fields
--- `target` already defines (directly or inherited) — a class's own
--- methods always win. Composition, not inheritance: no metatable link is
--- created, so a later change to `mixin` does not retroactively affect
--- `target`.
---@param target table
---@param mixin table
function M.include(target, mixin)
  for k, v in pairs(mixin) do
    if type(v) == "function" and target[k] == nil then
      target[k] = v
    end
  end
end

---@type Lib.Class
return M
