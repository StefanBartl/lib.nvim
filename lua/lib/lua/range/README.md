# `lib.lua.range`

Parse a comma-separated list of positive integers and inclusive ranges
(`"1-3,5,7"`) into a sorted, deduplicated `integer[]`.

Editor-independent — no `vim` API, usable and testable outside Neovim too.
Reusable anywhere a user types a short range spec and the caller needs a
concrete list: page ranges, line ranges, commit ranges.

## Usage

```lua
local range = require("lib.lua.range")

range.parse("1-3,5,7")          --> { 1, 2, 3, 5, 7 }
range.parse("5,5,1-3")          --> { 1, 2, 3, 5 }        -- deduplicated
range.parse("3-1")              --> { 1, 2, 3 }           -- reversed range normalized

local list, err = range.parse("x")
--> nil, "range: invalid token 'x'"

local list, err = range.parse("1-5", { max = 3 })
--> nil, "range: 5 is above max 3"
```

## API

`parse(spec, opts?)` returns `integer[]|nil, string|nil` — the sorted,
deduplicated list on success, or `nil` plus an error message.

`opts`:

| Field | Meaning |
| --- | --- |
| `min` | Reject the spec if any parsed number is below this |
| `max` | Reject the spec if any parsed number is above this |

Invalid input (non-numeric tokens, an empty spec, a non-string spec) also
returns `nil, err` rather than raising.
