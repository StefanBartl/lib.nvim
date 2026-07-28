# `lib.lua.json.decode`

`init.lua` is just a namespace marker (`return {}`, types live in
`@types/init.lua`) — all behavior lives in
[`to_string_array.lua`](to_string_array.lua), reached through the aggregator
as `require("lib.lua.json").decode` or directly as
`require("lib.lua.json.decode.to_string_array")`.

Despite the directory name, this is **not** a JSON text parser. It is a
wrapper that coerces an already-decoded value (or an arbitrary string/table/
scalar) into a `string[]`, for downstream APIs (UI lists, pickers, …) that
expect exactly that shape regardless of what the upstream JSON actually
contained.

## Usage

```lua
local to_str_arr = require("lib.lua.json.decode.to_string_array")

to_str_arr.is_array_like({ 1, 2, 3 })    --> true
to_str_arr.is_array_like({ [1] = 1, [3] = 3 })  --> false (gap at index 2)
to_str_arr.is_array_like({ a = 1 })      --> false
to_str_arr.is_array_like("x")            --> false (not a table)
```

`is_array_like` accepts only contiguous positive-integer keys starting at 1
(strict Lua array semantics) — a sparse or dictionary-shaped table is
rejected.

```lua
to_str_arr.table_to_string_array({ "a", "b", 3 })
  --> { "a", "b", "3" }              -- array-like: tostring() each element

to_str_arr.table_to_string_array({ b = 2, a = { x = 1 } })
  --> { "a: {\n  x = 1\n}", "b: 2" }  -- dict-shaped: sorted "key: value"
                                       -- pairs; nested tables via vim.inspect
```

Non-array-like tables are serialized one string per key, keys sorted by
`tostring(key)` for stable output, `"<key>: <value>"`. Nested table values are
rendered with `vim.inspect` rather than recursed into.

```lua
to_str_arr.ensure_string_array({ "a", "b" })  --> passed through table_to_string_array
to_str_arr.ensure_string_array("one\ntwo\n")  --> { "one", "two", "" }
                                                -- vim.split(v, "\n", { plain = true })
to_str_arr.ensure_string_array(42)            --> { "42" }
to_str_arr.ensure_string_array(true)          --> { "true" }
```

`ensure_string_array` is the one entry point meant for "I don't know what
shape this value is, give me a `string[]` no matter what": tables go through
`table_to_string_array`, strings are split on `\n` via `vim.split` (so a
trailing newline produces a trailing empty-string entry, matching
`vim.split`'s own behavior), and everything else becomes a single-element
array via `tostring`.
