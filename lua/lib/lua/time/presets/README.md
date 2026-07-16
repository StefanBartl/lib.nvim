# `lib.lua.time.presets`

Date-range preset resolver, pure Lua (`os.time`/`os.date`), no `vim.*`. Each
preset returns `{ from, to }` unix timestamps. All presets accept an
optional `now` (unix timestamp) so callers can get reproducible ranges in
tests instead of depending on the wall clock.

`last_week` is the last 7 full days ending at the start of today (not the
previous Mon-Sun calendar week).

## Usage

```lua
local presets = require("lib.lua.time.presets")

-- Fixed `now` for a worked, reproducible example:
-- 2026-07-14 15:30:00 local time
local now = os.time({ year = 2026, month = 7, day = 14, hour = 15, min = 30, sec = 0 })

presets.today(now)
-- { from = <2026-07-14 00:00:00>, to = now }

presets.yesterday(now)
-- { from = <2026-07-13 00:00:00>, to = <2026-07-14 00:00:00> }

presets.last_week(now)
-- { from = <2026-07-07 00:00:00>, to = <2026-07-14 00:00:00> }

presets.this_month(now)
-- { from = <2026-07-01 00:00:00>, to = now }

presets.this_quarter(now)
-- { from = <2026-07-01 00:00:00>, to = now }  (Q3 starts in July)

presets.this_year(now)
-- { from = <2026-01-01 00:00:00>, to = now }

presets.custom(now - 3600, now)
-- { from = now - 3600, to = now }

presets.custom(now, now - 3600)
-- nil, "from must be <= to"
```

## Returns

Every preset returns a single `{ from: integer, to: integer }` table
(unix timestamps), except `custom`, which returns `range, nil` on success
or `nil, err` when `from > to` or either argument isn't a number.
