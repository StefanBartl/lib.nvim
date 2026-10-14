# `lib.nvim.json.canonical`

The **canonical** JSON encoder of a machine contract: the same value gives the
same bytes on every machine, so the text can be hashed (`digest`, `etag`),
compared and kept as a golden file. Moved here from `tasks_nvim.json`
(tasks.nvim@921a0c4) so that `tasks-export/1` and `rules-export/1` write
identical bytes.

Use [`lib.nvim.json`](../README.md) for everyday encoding; use this one when the
bytes themselves are the contract. Reading JSON stays `vim.json.decode`.

## Why not `vim.json.encode`

It writes `{}` as `[]` (an empty Lua table has no type), orders keys as `pairs`
does, cuts a float to 16 digits and is only sometimes an error on `NaN`.

## Rules

- Object keys are **sorted by byte value** on every Lua: plain Lua 5.1 compares
  strings with `strcoll` (the locale's collation), so the encoder sorts with its
  own bytewise comparator (`bytes_less`) and LuaJIT output is unchanged. An
  object that may be empty is made with `object({})`; an array that may be empty
  is just `{}` (or `array({})`). `vim.NIL` is `null`.
- Neovim's own empty-object marker counts as an object: `vim.empty_dict()` and
  every `{}` that `vim.json.decode` returns are written as `{}`, so decode
  followed by encode keeps `{}` and `[]` apart. `array(vim.empty_dict())` is
  still `[]` (the explicit mark wins). (An addition to `tasks_nvim.json`, which
  did not know the marker; no existing document changes its bytes.)
- Numbers: a whole number below 2^53 has no fraction; any other number is
  written with the fewest digits that read back as the same number. `NaN`, `inf`
  and a whole number of 2^53 or more **raise** (a silent loss of digits is the
  worst answer a contract can give). `-0` is `0`.
- Strings: valid UTF-8 (every bad byte, overlong form, surrogate and value above
  U+10FFFF becomes U+FFFD); every control byte (the C1 controls U+0080 to U+009F
  too), `"`, `\`, U+2028, U+2029 and `<` are escaped, so the text can sit in a
  `<script>` block and be printed to a terminal as it is.
- No whitespace (the form that is hashed). `indent` writes the same document
  readable.
- A table that is neither a list nor an object (holes, mixed keys) raises; the
  message names the path (`$.a.b[1]`). Nesting deeper than 64 raises (a cycle),
  also through a `memo` table; the limit is checked while a text is computed,
  not when a remembered one is reused.

## Usage

```lua
local json = require("lib.nvim.json.canonical")

json.encode({ zebra = 1, apple = { 2 } })        --> {"apple":[2],"zebra":1}
json.encode({ meta = json.object({}), tags = {} }) --> {"meta":{},"tags":[]}
json.encode(doc, { indent = 2 })                 -- readable, for golden files

-- the big part of a document is written once for its digest and once for the answer
local entries = json.memo(big_list)              -- must not change afterwards
```

## API

| Function | Meaning |
|---|---|
| `encode(value, opts?)` | The canonical text. `opts.indent` (spaces per level) gives the readable form. Raises on a value JSON cannot hold. |
| `object(t?)` | Mark `t` as an object even when empty. |
| `array(t?)` | Mark `t` as an array even when empty (the default for an empty table). |
| `memo(t)` | Remember the compact text of `t`; the readable form ignores the mark. |
| `bytes_less(a, b)` | `a < b` by byte value, never by the locale. For `table.sort` of a list whose order is hashed (`contract.doc`'s `rev_of` uses it). |

`encode` raises with a plain message (no source position, see
[conventions](../../../../../docs/conventions.md)); a contract wraps it in
`pcall` and answers `internal`.
