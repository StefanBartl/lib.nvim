# `lib.lua.time.format`

Format a unix timestamp using a small set of named style presets, pure Lua
(`os.date`), no `vim.*`. Unknown/`nil` `fmt` falls back to `"iso"`.

## Usage

```lua
local format = require("lib.lua.time.format")

-- ts = 2026-07-14 14:32:05 UTC
local ts = os.time({ year = 2026, month = 7, day = 14, hour = 14, min = 32, sec = 5 })

format.format_timestamp(ts, "iso", { utc = true })
-- "2026-07-14T14:32:05"

format.format_timestamp(ts, "human", { utc = true })
-- "Jul 14, 2026 14:32"

format.format_timestamp(ts, "short", { utc = true })
-- "2026-07-14"

format.format_timestamp(ts, "log", { utc = true })
-- "[2026-07-14 14:32:05]"

format.format_timestamp(ts, "filename", { utc = true })
-- "20260714_143205"

format.format_timestamp(ts, "unix")
-- "1783514725" (example value; exact number depends on ts)

format.format_timestamp(ts, "bogus", { utc = true })
-- falls back to "iso": "2026-07-14T14:32:05"
```

## Returns

| Function                    | Returns                                             |
| ---------------------------- | ------------------------------------------------------ |
| `format_timestamp(ts,f,o)`   | `string` — formatted timestamp per the requested style |
