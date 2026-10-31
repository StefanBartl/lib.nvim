# `lib.lua.patterns.flyweight`

> Pattern: Flyweight · Group: structural · Stage: `idea`
> Status: idea pool — may bring no benefit in Lua, kept as a reference.

Share identical immutable objects: `get(...)` returns the one instance per key.

## The pattern in one paragraph

When very many objects are equal in their intrinsic state, keep one and hand it out by key. The factory runs once per key. The default key tags each argument with its type and length (so `1` and `"1"`, `nil` and `"nil"` stay apart); `opts.key` overrides it; `opts.weak` lets unused instances be collected.

## Usage

```lua
local flyweight = require("lib.lua.patterns.flyweight")

local hl = flyweight.new(function(fg, bg) return { fg = fg, bg = bg } end)
hl:get("red", "black") == hl:get("red", "black") --> true
```

## API

| Function | Does |
| --- | --- |
| `new(make, opts)` | `opts.key`, `opts.weak` |
| `f:get(...)` | shared instance |
| `f:size()` / `f:clear()` | inspect / empty |

## When it helps / when it does not (Lua view)

- **Helps when:** thousands of equal small objects are created in a hot path (highlight specs per cell, parsed tokens).
- **Does not help when:** objects are few or mutated by their users (sharing a mutable object is a bug). Lua already interns strings, and a table lookup can cost more than a small allocation. This module may bring no benefit.
- **Cheaper alternative in Lua:** a local cache table keyed by a string.

## Related

- `lib.lua.memo` (cache function results), `lib.lua.patterns.object_pool` (recycle instead of share), Prototype.

## Tests

`TESTS/patterns_flyweight_spec.lua`: sharing, distinct keys, key separator, custom key, clear, weak cache.
