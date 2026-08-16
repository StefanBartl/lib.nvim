# `lib.lua.class`

Prototype OOP: `new`/`extend`/`include`, pure Lua — no `vim` API, works
outside Neovim too.

Two modules in this codebase already hand-roll the classic `Name = {};
Name.__index = Name` prototype independently
([`lib.lua.memo.lru`](../memo/lru.lua),
[`lib.nvim.ui.kit.surface`](../../nvim/ui/kit/surface.lua)) — this
generalizes that shape and adds inheritance (the classic Lua two-level
metatable chain) and mixin composition, neither of which existed anywhere
in the codebase before. Not retrofitted onto `lru`/`surface` — they keep
their own hand-rolled version; this is for new code.

## Usage

```lua
local class = require("lib.lua.class")

local Animal = class.new("Animal")
function Animal:init(name)
  self.name = name
end
function Animal:speak()
  return self.name .. " makes a sound"
end

local rex = Animal.new("Rex")
rex:speak() --> "Rex makes a sound"

local Dog = Animal:extend("Dog")
function Dog:speak() -- override
  return self.name .. " barks"
end

local fido = Dog.new("Fido") -- init inherited from Animal, unchanged
fido:speak() --> "Fido barks"
fido.name    --> "Fido"
```

### Mixins

```lua
local Loud = {
  shout = function(self)
    return self.name:upper() .. "!!!"
  end,
}

class.include(Dog, Loud)
fido:shout() --> "FIDO!!!"
```

`include` copies function fields from the mixin onto the target, skipping
anything the target already defines (own methods always win). It is
composition, not inheritance — no metatable link is created, so a later
change to the mixin table does not retroactively affect classes that
already included it.

## Returns

| Function                | Returns | Meaning                                                       |
|---------------------------|---------|-------------------------------------------------------------------|
| `M.new(name)`              | `table` | A new root class — `.new(...)` builds instances, `:extend(name)` subclasses it |
| `Class.new(...)`           | `table` | A new instance; calls `init(self, ...)` if defined (inherited counts) |
| `Class:extend(name)`       | `table` | A subclass whose method lookup falls back to `Class`          |
| `M.include(target, mixin)` | —       | Copies `mixin`'s functions onto `target` (no return value)    |
