# `lib.lua.config`

Pure helpers for the "defaults + user overrides" config store pattern: the
`setup(opts)` / `get(path)` pair almost every plugin's `config` module
implements.

Extracted from **two** byte-identical copies — cascade.nvim's and
spotlight.nvim's `config/init.lua` each had their own `deep_merge` and
`M.get`. Both plugins now keep only the parts that are actually specific to
them (defaults, validation/normalization, `M.options`/`M.issues` state) and
delegate the merge and the lookup here.

```
lib.lua.config/
├── init.lua       -- copy, deep_merge, get
├── schema/        -- check, check_record, infer (see schema/README.md)
└── @types/        -- LuaLS types (Lib.Config)
```

Entry point is `require("lib.lua.config")`.

## Why not `lib.lua.tables.core.deep_merge`

That function already exists, but it solves a different problem: it mutates
`dst` in place, and it recurses into *every* nested table — including
list-like ones. For a config default like `{ groups = { "a", "b", "c" } }`
overridden with `{ groups = { "x" } }`, that would merge index-by-index and
leave `"b"`/`"c"` behind index 1's replacement, instead of the override fully
replacing the list. That is exactly the surprise a config store must not
have: a user who explicitly redefines a list expects it gone, not merged.

`lib.lua.config.deep_merge` copies `base` instead of mutating it, and
replaces a list-like table (per `lib.lua.tables.core.is_array`, checked on
the override side) wholesale rather than recursing into it.

## What the result shares

Nothing. Every table in the result is new, including the branches the
override never mentions and the tables that only the override has. Without
that, a plugin that writes into its live config (`cfg.state.last = …`) would
change `DEFAULTS` through the shared branch, and the next `setup()` would no
longer start from the real defaults; writing into a table the caller passed
in would change their `opts` the same way. Functions are kept as they are,
metatables are carried over by reference. `vim.tbl_deep_extend("force", {},
DEFAULTS, opts)` does **not** have this property: a key only one side has is
taken by reference (checked on Neovim 0.12.2).

## Which tables merge, which replace

| Override value | Default value | Result |
| -------------- | ------------- | ------ |
| map            | map           | merged key by key |
| non-empty list | anything      | replaces |
| map or list    | list          | replaces |
| `{}`           | list or `{}`  | `{}` (no entries) |
| `{}`           | map           | the default map, unchanged |
| scalar, `false`| anything      | replaces |

The `{}` row is why an empty table can not be decided from the override side
alone: `{ groups = {} }` means "no groups" where the default is a list and
"nothing to override" where it is a map.

`copy(t)` is the deep copy `deep_merge` uses: cyclic and repeated references
stay cyclic and repeated inside the copy.

## API

```lua
local config = require("lib.lua.config")

-- In a plugin's own config module:
local M = { options = DEFAULTS }

function M.setup(opts)
  M.options = config.deep_merge(DEFAULTS, opts or {})
end

function M.get(path)
  return config.get(M.options, path)
end

M.get("lists.checkbox.states")  -- dot-separated path into M.options
```

`get(tbl, path)` returns `nil` on a missing key, a non-table path
descending through a scalar, or a non-string `path` — it never errors.
