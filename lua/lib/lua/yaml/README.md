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
