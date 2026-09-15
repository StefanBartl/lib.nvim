# `lib.lua.null`

A single shared "null" sentinel for every `lib.lua.*` format module. Pure Lua,
no `vim` API.

## Why this exists

Lua's `nil` cannot be stored as a table value (`t.a = nil` deletes the key), so
none of `json`/`yaml`/`xml` can represent an explicit null the way JSON/YAML/XML
themselves do. Each format module used to face that problem alone; this module
gives them one shared answer, which matters the moment a value crosses formats
(decode JSON, re-encode as YAML) — both sides need to agree on what "this is
null" looks like as a Lua value.

```lua
local null = require("lib.lua.null")

null.is_null(null.NULL) --> true
null.is_null(nil)       --> false (real Lua nil is not the sentinel)
null.is_null({})        --> false (an empty table is not null)
```

## Who uses it

- `lib.nvim.json.decode` normalizes `vim.json.decode`'s own `vim.NIL` into
  `null.NULL` before handing the result to callers, so nothing above it needs
  to know `vim.NIL` exists.
- `lib.lua.json.encode` encodes `null.NULL` as the JSON literal `null`.
- `lib.lua.yaml.encode` encodes `null.NULL` as the YAML literal `null` (a
  decoded YAML document represents null by omitting the key/element instead —
  see `lib.lua.yaml`'s own README for why that direction stays asymmetric).
