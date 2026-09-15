# `lib.lua.yaml`

A **deliberately minimal**, dependency-free YAML-ish decoder, pure Lua. Not
spec-complete: no anchors/aliases, no multi-document streams, no flow style
(`{}`/`[]`), no block scalars (`|`/`>`). See the module doc comment in
`init.lua` for the exact supported subset.

YAML `null`/`~`/empty scalars cannot be stored as Lua `nil` inside a table,
so this decoder represents "null" by **omitting** the key (maps) or
**skipping** the element (lists) rather than using a sentinel — a missing
key can therefore mean either "absent" or "explicitly null".

## Usage

```lua
local yaml = require("lib.lua.yaml")

local text = [[
name: demo
version: 2
enabled: true
tags:
  - alpha
  - beta
nested:
  host: localhost
  port: 8080
]]

local data, err = yaml.simple_parse(text)
-- err = nil
-- data = {
--   name = "demo",
--   version = 2,
--   enabled = true,
--   tags = { "alpha", "beta" },
--   nested = { host = "localhost", port = 8080 },
-- }
```

## Returns

| # | Type            | Meaning                                                  |
|---|------------------|-----------------------------------------------------------|
| 1 | `table\|nil`      | Decoded data on success, `nil` on malformed input          |
| 2 | `string\|nil`     | `nil` on success, error message (e.g. bad indentation) otherwise |

## Encoding ([`encode.lua`](encode.lua))

The counterpart to `simple_parse`, covering the same subset (no anchors, no
flow style, no block scalars). Encoder output is decoder input — checked
against `simple_parse` in `TESTS/`, not just eyeballed.

```lua
yaml.encode({ name = "Ana", tags = { "a", "b" } })
-- "name: Ana\ntags:\n  - a\n  - b"

yaml.encode(value, { indent = 4 })  -- 4 spaces per level instead of 2
```

- Strings are quoted (single quotes) only when a bare word would decode
  differently (`"true"`, `"42"`, `"null"`, one containing `": "`, ...).
- `lib.lua.null.NULL` (the shared sentinel — see that module) encodes as the
  bare word `null`. An *empty* nested table (`{}`) has no inline form in
  this subset and is emitted as a bare `key:`/`-` line instead — `null`, as
  a value, and an empty table both then decode back as "key omitted" per
  `simple_parse`'s own null-as-absence design, not a new asymmetry.
- A list item that is a map with more than one key cannot use the
  `- key: value` one-line shorthand (the decoder only reads one key that
  way) — the encoder always uses the bare-`-`-plus-indented-block form for
  map items, which round-trips regardless of key count.
