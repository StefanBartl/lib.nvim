# `lib.lua.json`

Aggregates `lib.lua.json.decode` and `lib.lua.json.encode` under one table.
Both are pure Lua — no `vim` API — so they work outside Neovim too.

```lua
local json = require("lib.lua.json")
```

**`json.decode` is not a JSON parser.** There is no "parse this JSON text
into a Lua value" function here — that's `vim.json.decode` (or an external
decoder) upstream of this module. What lives under `decode` is a set of
adapters that coerce an *already-decoded* JSON-shaped value (or an arbitrary
string/scalar) into a `string[]`, for callers (typically UI lists/pickers)
that need one regardless of what shape the input happened to be:

```lua
json.decode.is_array_like({ 1, 2, 3 })          --> true
json.decode.is_array_like({ a = 1 })            --> false
json.decode.table_to_string_array({ "a", "b" }) --> { "a", "b" }
json.decode.table_to_string_array({ b = 2, a = 1 })
  --> { "a: 1", "b: 2" }   (sorted by key, "key: value" per entry)
json.decode.ensure_string_array("one\ntwo")     --> { "one", "two" } (split on \n)
json.decode.ensure_string_array(42)             --> { "42" }
```

See [`decode/README.md`](decode/README.md) for the full detail.

`json.encode` is a callable module — pure-Lua JSON *encoder*, the actual
counterpart to `vim.json.encode`, deliberately not delegating to it so
encoding behaves identically on every platform/runtime:

```lua
json.encode({ a = 1, list = { 1, 2, 3 } })  --> '{"a":1,"list":[1,2,3]}'
json.encode.pretty({ a = 1 })               --> multi-line, 2-space indent
```

See [`encode/README.md`](encode/README.md) for options and error semantics.
