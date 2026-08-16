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
