# `lib.lua.numeral`

Numeral conversion helpers, pure Lua: `roman` (Roman numerals, 1-3999) and
`alpha` (bijective base-26, spreadsheet-column style: `a`, `b`, …, `z`,
`aa`, `ab`, …).

## Usage

```lua
local numeral = require("lib.lua.numeral")

-- Roman numerals
local r = numeral.roman.to_roman(1994)
-- r = "MCMXCIV"

local n, err = numeral.roman.to_int("mcmxciv")
-- n = 1994, err = nil

local bad, err2 = numeral.roman.to_int("IIII")
-- bad = nil, err2 = "invalid roman numeral" (non-canonical; canonical form is "IV")

-- Bijective base-26 ("alpha")
local a = numeral.alpha.to_alpha(27)
-- a = "aa"

local i = numeral.alpha.to_int("AA")
-- i = 27
```

Submodules can also be required directly: `require("lib.lua.numeral.roman")`,
`require("lib.lua.numeral.alpha")`.

## Returns

| Function                    | Returns                                                        |
| ---------------------------- | --------------------------------------------------------------- |
| `roman.to_roman(n)`          | `string, nil` on success; `nil, string` (`"out of range"`) otherwise |
| `roman.to_int(s)`            | `integer, nil` on success; `nil, string` (`"invalid roman numeral"`) otherwise |
| `alpha.to_alpha(n)`          | `string, nil` on success; `nil, string` (`"out of range"`) otherwise |
| `alpha.to_int(s)`            | `integer` on success; `nil` otherwise                          |
