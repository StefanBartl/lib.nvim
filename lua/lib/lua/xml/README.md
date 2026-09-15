# `lib.lua.xml`

A **deliberately minimal**, dependency-free XML decoder + encoder, pure Lua —
same spirit as `lib.lua.yaml`: not spec-complete, no namespace resolution, no
DTD parsing beyond skipping over one. See the doc comments in
`decode.lua`/`encode.lua` for the exact supported subset.

## Shape

Every element decodes to (and encodes from) the same plain tree:

```lua
{ tag = "name", attrs = { ["attr"] = "value", ... }, children = { ... } }
```

`children` is an **array** mixing nested element tables and plain Lua strings
(text nodes). This is a plain tree, not an attempt to map XML onto a
JSON-like object: repeated sibling tags are **not** collapsed into an array
under one key, and there is no single "the value of this element" field
distinct from its children. Doing that generically is ambiguous without a
schema (which sibling repeats become a list? which attribute becomes "the"
value?) — this module leaves that decision to the caller instead of guessing.
One consequence: `lib.lua.tables.path_flatten` on a decoded element produces
mechanical paths like `children.1.attrs.id`, not a human-curated summary —
see [`data.nvim`'s own architecture notes](https://github.com/StefanBartl/data.nvim/blob/main/docs/architecture.md)
for how it uses this in practice.

## Usage

```lua
local xml = require("lib.lua.xml")

local tree, err = xml.decode('<user id="1"><name>Ana</name></user>')
-- tree = {
--   tag = "user",
--   attrs = { id = "1" },
--   children = {
--     { tag = "name", attrs = {}, children = { "Ana" } },
--   },
-- }

xml.encode(tree)          --> '<user id="1"><name>Ana</name></user>'  (compact, one line)
xml.encode.pretty(tree)   --> multi-line, 2-space indent
xml.encode(tree, { indent = 4 })
```

## Returns

| # | Type            | Meaning                                                  |
|---|------------------|-----------------------------------------------------------|
| 1 | `table\|nil`      | Decoded element tree on success, `nil` on malformed input   |
| 2 | `string\|nil`     | `nil` on success, error message otherwise                  |

Unlike `lib.lua.yaml.encode` (whose block-style subset has no single-line
form), `lib.lua.xml.encode` is compact by **default** and multi-line only
with an explicit `indent` — the same convention as `lib.lua.json.encode`.
