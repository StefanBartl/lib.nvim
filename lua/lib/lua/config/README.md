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
├── init.lua       -- deep_merge, get
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
