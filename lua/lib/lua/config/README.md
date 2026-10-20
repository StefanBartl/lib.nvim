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
├── init.lua       -- copy, deep_merge, merge_into, get, new
├── instance.lua   -- the config object `new` makes
├── schema/        -- check, check_record, infer (see schema/README.md)
└── @types/        -- LuaLS types (Lib.Config)
```

Entry point is `require("lib.lua.config")`.

## The config object: `new`

A plugin's whole `config/init.lua`:

```lua
local DEFAULTS = require("myplugin.config.DEFAULTS")

return require("lib.lua.config").new(DEFAULTS, {
  name = "myplugin",
  notify = require("lib.nvim.notify").create("[myplugin]").warn,
})
-- cfg.setup(opts)   cfg.get("ui.width")   cfg.issues()   cfg.reset()
```

Every change (`setup`, `layer`, `reset`) recomputes the config from scratch: a
fresh, alias-free copy of `DEFAULTS`, the layers on top in rank order, then
`resolve`. Nothing is merged onto the previous state, so an option dropped from
the user's config is gone after the next `setup()`, and nothing written into the
live config can reach `DEFAULTS`.

| Call | Does |
| ---- | ---- |
| `setup(opts)` | sets the layer `"setup"`; `setup(nil)` is exactly the defaults |
| `layer(name, opts)` | sets or (`nil`) removes a named layer; the others stay |
| `get(path?)` | the live table, or the value at a dot path. Read it, do not write to it |
| `snapshot()` | a deep copy to write to |
| `source(path)` | the layer a value comes from, `"default"`, or `nil` |
| `issues()` | what the layers dropped, then what `resolve` degraded; for `:checkhealth` |
| `reset()` | drops every layer |
| `verify()` | the path at which the live table was written to, or `nil` (checking mode) |

### What the options do

Each layer is checked once, when it is set: `normalize` (on a copy), then the
schema inferred from `DEFAULTS` — an unknown key gets a did-you-mean hint, a
value of the wrong type falls back to the default — and the rejected part is
left out. `notify` gets the problems of that layer once, not on every later change.

| `spec` key | Meaning |
| ---------- | ------- |
| `name` | prefix for errors; default `"config"` |
| `schema` | exceptions to the inferred schema, by dotted path: a `false` default that also takes a string, an enum, a bound, an open map (see `lib.lua.config.schema`) |
| `optional` | keys that are allowed but have no default (an opt-in feature whose absence means off) |
| `merge` | per dotted path `"replace"` (the user's value replaces, `{}` included) or `"entries"` (a map of independent entries: a named one replaces as a whole, `false` removes a default one, the rest stay). An `entries` path is an open table unless `schema` says more; allow `false` there if removal should pass the check |
| `layers` | rank of the layers, lowest first, `"setup"` among them; default `{ "setup" }`. Two owners of one plugin (the install spec and another plugin) each write their own layer; a layer's problems carry its name |
| `normalize(opts, issues, layer)` | before the check, on a private copy: `keymaps = false` to `{ enable = false }`, an old key name to the new one |
| `resolve(cfg, issues)` | after the merge: derived values, joint constraints (`min <= max`) |
| `on_change(cfg, prev)` | after every change: clear caches, rebuild lookups |
| `opaque` | dotted paths whose value is a table of the user's own that must stay that very table: a loaded module handed in as an option (`neotree.quarantine = require("x")`), an object with state. The copy every other table gets would be a different table; the original is put back after the merge, only where the value passed the check, and from the highest layer that names the path (a higher layer never writes into it; with `stable` it is replaced, not assigned into; the checking mode does not compare its content) |
| `stable` | write into the same table every time, so a module that stashed `cfg.get().picker` keeps seeing the current values |
| `notify(message)` | called with a layer's problems when it is set |

`get()` before any `setup()` is the defaults (computed on first use).

### Checking mode

`get()` hands out the live table, so a plugin that writes into it changes its own
config until the next change. In the specs of a plugin, turn the checking mode on
(`require("lib.lua.config").set_checked(true)`, or `LIB_CONFIG_CHECKED=1`): the
next `get()` after a write fails with the plugin name and the path, and the fix
is to write to `snapshot()`. It is a check at the next read, not at the write:
LuaJIT has no `__pairs`, `__len` or `__ipairs`, so a read-only proxy could not be
iterated.

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
