# `lib.lua.patterns.composite`

> Pattern: Composite · Group: structural · Stage: `impl`

Treat a group like one element: a call on the group is made on every child; groups can nest.

## The pattern in one paragraph

Callers do not care whether they hold one element or many. A group forwards a method call to each child and returns the results as a list; a nested group yields a nested list. One failing child does not stop the others, its error is returned separately. Children without the method are skipped.

## Usage

```lua
local composite = require("lib.lua.patterns.composite")

local all = composite.new({ statusline_a, statusline_b })
local results, errors = all:call("refresh", "!")
all:add(composite.new({ c, d }))
```

## API

| Function | Does |
| --- | --- |
| `new(children)` | copies the list |
| `g:add(child)` / `g:remove(child)` / `g:size()` | manage children |
| `g:call(method, ...)` | `results, errors` |

## When it helps / when it does not (Lua view)

- **Helps when:** "do X on all of them" recurs and the elements may themselves be groups (progress styles, statusline pieces, multiple watchers).
- **Does not help when:** a flat list and a `for` loop are enough, which is most of the time.
- **Cheaper alternative in Lua:** `for _, c in ipairs(list) do c:refresh() end`.

## Related

- `lib.nvim.progress` (a handle fans out to several styles, written by hand), Observer, Iterator.

## Tests

`TESTS/patterns_composite_spec.lua`: fan-out, nesting, add/remove, error isolation, skipping, input list untouched.
