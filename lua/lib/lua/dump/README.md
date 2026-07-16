# `lib.lua.dump`

Recursive Lua value dumper, pure Lua — an alternative/complement to
`vim.inspect` for tables/metatables/functions/threads/userdata, with a hard
recursion-depth limit against cyclic tables or huge structures.

## Usage

```lua
local dump = require("lib.lua.dump")

print(dump.to_string(some_value))
local lines = dump.to_lines(some_value, { max_depth = 10 })
```

## Functions

- `to_lines(value, opts?)` — returns an array of indented report lines.
  `opts.max_depth` defaults to `30`.
- `to_string(value, opts?)` — same, newline-joined into a single string.

Tables with a metatable get both their own fields and the metatable's
fields dumped (nested under a `(metatable)` marker), rather than one
replacing the other.
