# `lib.lua.json.encode`

Pure-Lua JSON encoder — the actual counterpart to `lib.lua.json.decode`.
Editor-independent by design (no `vim` API), so it behaves identically in
plain Lua, LuaJIT and Neovim. `vim.json.encode` is deliberately **not** used
internally, even when available — this module guarantees the same output on
every platform/runtime rather than inheriting whatever `vim.json.encode`
happens to do.

The module table is callable: `require(...)(value)` is the same as
`require(...).encode(value)`.

## Usage

```lua
local encode = require("lib.lua.json.encode")

encode({ a = 1, list = { 1, 2, 3 } })   --> '{"a":1,"list":[1,2,3]}'
encode.pretty({ a = 1 })                --> '{\n  "a": 1\n}'  (2-space indent)
encode({ a = 1 }, { indent = 4 })       --> 4-space indent
encode({ b = 2, a = 1 }, { sort_keys = false })  -- key order becomes unspecified
```

Both `encode` and `pretty` return `encoded_string, nil` on success, or
`nil, err_message` on failure — the encoder never throws.

## Semantics

* **strings** — escaped per RFC 8259, control characters as `\u00XX`.
* **numbers** — integers render without a trailing `.0`; `NaN`/`Infinity` are
  a hard error (`nil, "cannot encode NaN"` / `"cannot encode Infinity"`).
* **booleans / `nil`** — `true`/`false`/`null`. A bare top-level `nil` encodes
  to `"null"`.
* **tables** — contiguous `1..n` integer keys encode as a JSON array
  (empty table `{}` also encodes as `"[]"`, mirroring
  `decode.is_array_like`'s treatment of `{}` as array-like); anything else
  encodes as a JSON object. Object keys must be strings or numbers (any other
  key type is an error) and are stringified; by default they are **sorted**
  for deterministic output (`opts.sort_keys = false` to skip sorting).
* **cycles, functions, userdata, threads** — `nil, err` naming the offending
  type or "cyclic table".

## Options (`Lib.JSON.EncodeOpts`)

| Field | Default | Meaning |
| --- | --- | --- |
| `indent` | `nil` (compact) | Integer = that many spaces per level; string = literal indent unit (e.g. `"\t"`); `nil`/`0`/`""` = single-line compact output. |
| `sort_keys` | `true` | Sort object keys. |

`encode.pretty(value, opts)` is `encode` with `indent` defaulted to `2` when
the caller doesn't set one explicitly.
