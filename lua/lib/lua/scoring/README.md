# `lib.lua.scoring`

Additive score: a base value plus a list of **named** bonuses and maluses, clamped to a range, with a
`details` breakdown that shows every contribution one by one (what made 87 out of 100, not just 87).
Pure Lua, no `vim`. Generalised from the scoring of `learn-cli.nvim`.

## Usage

```lua
local scoring = require("lib.lua.scoring")

local s = scoring.new({ base = 50, min = 0, max = 100 })
s:bonus("no hints used", 20)
s:malus("typos", 7)
s:bonus("fast", 40, elapsed < 30) -- counted only when the condition is true

local r = s:result()
r.score    --> 100  (50 + 20 - 7 + 40 = 103, clamped)
r.raw      --> 103  (unclamped, unrounded)
r.clamped  --> "max" ("min", or nil when nothing was cut)
r.details  --> { { name = "no hints used", delta = 20, total = 70 },
                 { name = "typos",         delta = -7, total = 63 },
                 { name = "fast",          delta = 40, total = 103 } }
```

Without the builder: `scoring.compute({ { name = "a", delta = 3 }, ... }, { base = 1 })`.

## API

| Call | Meaning |
|---|---|
| `scoring.new(opts?)` | Builder. `opts.base` (default 0), `opts.min`, `opts.max` (default none), `opts.round` = `"floor"`, `"ceil"`, `"nearest"` or `false`. |
| `b:add(name, delta, applies?)` | Signed contribution. `applies = false` leaves it out entirely (it is not listed either). Returns the builder. |
| `b:bonus(name, points, applies?)` | Same as `add`. |
| `b:malus(name, points, applies?)` | Subtracts the magnitude: `malus("typos", 7)` and `malus("typos", -7)` are both -7. |
| `b:result()` | `{ score, raw, base, clamped, details }`. May be read repeatedly; the builder keeps collecting. |
| `scoring.compute(entries, opts?)` | The same for a ready list `{ name, delta, applies? }`. |

Rounding happens after the clamp. A non-finite number, an empty name, `min > max` or an unknown rounding is
an error that names the module.
