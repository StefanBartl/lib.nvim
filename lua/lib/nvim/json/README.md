# `lib.nvim.json`

Decode/encode arbitrary JSON strings — not just files. `lib.lua.json` is
pure Lua and only exposes an encoder plus array-shape decode *helpers*, not
a general JSON-string parser; this module lives in the `lib.nvim`
(editor-adapter) namespace where `vim.json` is always available, and wraps
it in the same `value, err` contract used across `lib.nvim`.

For JSON *files* see [`lib.nvim.fs.json`](../fs/json/README.md), which is
built on this module.

## Usage

```lua
local json = require("lib.nvim.json")

local tbl, err = json.decode('{"a":1}')
-- tbl = { a = 1 }

local str, err2 = json.encode({ a = 1 })
-- str = '{"a":1}'
```

## Returns

| Function             | Returns              | Meaning                                                        |
|-----------------------|-----------------------|------------------------------------------------------------------|
| `M.decode(str)`        | `any, string\|nil`     | Decoded value, or `nil` + error (`"invalid JSON: ..."`)         |
| `M.encode(value, opts)`| `string\|nil, string\|nil` | JSON string, or `nil` + error — delegates to `lib.lua.json.encode` |

## Error strings are user-presentable

`M.decode`'s `err` is meant to be forwarded straight into a notification, so
it never carries a `file:line:` prefix:

```
invalid JSON: Expected object key string but found invalid token at character 2
invalid JSON: max nesting depth (64) exceeded while normalizing JSON null values
```

The first comes from `vim.json.decode` (raised in C, so unprefixed anyway);
the second is this module's own depth guard, which raises with `error(msg, 0)`
precisely so both failure modes read alike. Consumers should forward `err`
verbatim rather than pattern-matching a path prefix off the front — see
[docs/conventions.md](../../../../docs/conventions.md#returned-error-strings-carry-no-source-position).
