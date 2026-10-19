# `lib.lua.config.schema`

Declarative option schemas for plugin configs: an unknown key or a value of
the wrong type is reported, and the rejected part is left out of the result so
the default applies (ERR-50 / ERR-22). Pure Lua, no `vim.*`.

Taken from filetree.nvim's `config/schema.lua`; filetree now uses this module
and keeps only what is its own (the always-accepted `autocmds_enabled` and the
per-feature registry).

## It only looks

`check` never changes its input and never writes a default. A rejected value
comes back as `nil` with one line in `issues`; what takes its place (the
default, a placeholder) is the caller's decision. `lib.lua.config.new` falls
back to the default; a repairing layer such as `lib.nvim.json.sanitize` can sit
on the same check and fill in placeholders instead.

## Spec forms

| Spec | Accepts |
| ---- | ------- |
| `"boolean"`, `"number"`, `"string"`, `"table"`, `"function"` | that Lua type |
| `"string\|false"` | a union; the token `false` is the literal `false` ("a string, or false to switch off") |
| `"keymap"` | a key, a list of keys, or `false` |
| `{ "number", min = 0, max = 10 }` | inclusive bounds; NaN and +-inf never pass |
| `{ "string", enum = { "a", "b" } }` | a closed value set (string values only) |
| `{ "table", fields = { key = spec } }` | a closed record: unknown keys are reported |
| `{ "table", of = spec }` | an array or open map whose every value matches `spec` |
| `{ "table" }` | any table |

A rejected element inside an `of` table drops the whole table: leaving one
entry out of an array would shift or punch a hole in the rest, which is worse
than the default list.

## API

```lua
local schema = require("lib.lua.config.schema")

local issues = {}
local kept = schema.check(value, spec, "picker.engine", issues)   -- value or nil
local clean = schema.check_record(opts, fields, "", issues)        -- new table, bad keys left out
schema.describe_got(value)   -- how a rejected value reads in a message: 5, false, "x", table
```

Messages name the dotted path (`option 'ui.sizes.w' must be a number, got "x"
-- using the default`) and, for a typo, the nearest known key by edit distance
(`unknown option 'ui.sizess' (did you mean 'ui.sizes'?)`). A record's keys are
checked in sorted order, so the same input always reports in the same order.

## `infer`: the schema out of DEFAULTS

```lua
local spec = schema.infer(DEFAULTS, {
  border = "string|false",                          -- the default is false, a string is fine too
  ["picker.engine"] = { "string", enum = { "fzf", "native" } },
  ["picker.extra"] = "number",                      -- a key with no default at all
  custom_aliases = { "table", of = "string" },      -- open map, the user picks the keys
})
```

What a default value implies:

| Default | Spec |
| ------- | ---- |
| boolean, number, string, function | that type |
| a non-empty map | a closed record of its keys |
| a list, or `{}` | any table (the shape of a user's entries is not in the default) |

Exceptions are dotted paths, applied shortest first, so one for a branch is in
place before one for a key inside it. An exception replaces what was inferred
at that path or adds the key to the record above it. One below a scalar or
below an open table is an error. A key that itself contains a dot can not be
reached by an exception.

A `false` default is inferred as `boolean`: where `false` means "off" and a
string is also allowed, say so with an exception.
