# `lib.nvim.contract.errors`

The error vocabulary of a **machine contract** (`tasks-export/1`, `rules-export/1`,
...): a stable `code`, a `message`, and whether asking again can help
(`retryable`). Moved here from `tasks_nvim.errors` (tasks.nvim@6bc8d99); the one
domain-specific part, the matching of a plugin's own messages, is now a hook.

## Codes

`M.CODES` (sorted): `conflict`, `exists`, `forbidden`, `internal`,
`invalid_argument`, `io`, `lock_stuck`, `locked`, `not_found`,
`payload_too_large`, `rollback_incomplete`, `unsupported_schema`.

The list is **enforced**: a code that is not in it (a typo, a plugin's own word)
is answered as `internal`, with the message naming it (`unknown error code
"lockd": busy`) and `retryable = false`. That holds for `fail`, for an error
table or `info.code` that reaches `classify`, and for a pattern's code; it never
raises, so a slip cannot take the host down from its error path.
`check_patterns` refuses such a pattern where it is handed in. `is_code(code)`
asks the list.

## Usage

```lua
local errors = require("lib.nvim.contract.errors")

-- the plugin's own message patterns, handed in once
local PATTERNS = {
  { code = "not_found", find = { "unknown family", "source not found" } },
  { code = "invalid_argument", find = { "nothing to set" } },
}

local function classify(err, info)
  return errors.classify(err, info, { patterns = PATTERNS })
end

classify("unknown family 'X'")                  --> { code = "not_found", ... }
classify("file changed", { code = "conflict", id = "LUA-12" })
--> { code = "conflict", message = "file changed", retryable = false, details = { id = "LUA-12" } }
```

## API

| Function | Meaning |
|---|---|
| `fail(code, message, retryable?)` | An error table; `retryable` only when it is the boolean `true`. A `code` that is not in `CODES` gives `internal` (above). |
| `is_code(code)` | Whether `code` is one of `CODES`. |
| `scrub(text)` | A Lua error text without where the plugin is installed (`<path>/lua/x/a.lua:3: boom` becomes `x/a.lua:3: boom`). Linear in the length of the text, a long token included. **Limit:** a token (what lies between whitespace or quotes) is cut at its last `/lua/`, so a path with a space keeps its head (`/Users/Jane Roe/.../lua/x/a.lua` becomes `/Users/Jane x/a.lua`) and a path with no `lua` directory is not touched. LuaJIT already shortens a chunk name of more than 59 characters to `...` plus its tail, which hides most of that head. |
| `text(value)` | Whatever came back as an error, as a text: a string as it is, a number or boolean as it prints, a table by its own `__tostring` or its string `message`, anything else (a function, a userdata, a table with neither) `error value of type <type>`. Never an address (`table: 0x...` differs on every call) and never a throw. |
| `check_patterns(patterns)` | `nil` when `patterns` is a list of `{ code = string, find = string[], retryable? }`, else a message that names the first fault (`patterns[2].find must be a list of strings`; no position, it is a value). `contract.api.make` calls it and raises at construction; a plugin that hands `opts.patterns` to `classify` itself can call it once. |
| `classify(err, info?, opts?)` | Turn whatever came back into the error a document carries (below). |
| `DETAIL_KEYS` | Keys of `info` a document may show: `id`, `key`, `expected`, `actual`, `written`, `writes`. Never a path. |

`classify`:

1. an `err` that already is an error table (has a `code`) is returned as it is
   (with an unknown code: as `internal`, its `details` kept);
   any other value that is not a string is made a text by `text` (this differs
   from `tasks_nvim.errors`, which used `tostring` and so printed
   `table: 0x...`);
2. with `info.code` (the third value some functions give; a value that is no
   table, such as `true`, is ignored) the code comes from the
   source; `locked` is always retryable; `details` carries only `DETAIL_KEYS`
   (or `opts.detail_keys`);
3. otherwise the **text** is matched: first `opts.patterns` (the plugin's own),
   then the built-in ones, each tried in this order: `not_found` (`is not a
   directory`, `no such`), `exists` (`already exists`), `rollback_incomplete`,
   `io` (`cannot list/read/write/create/update/lock`, `permission`), `locked`
   (`is being written`, retryable), `lock_stuck` (`remove it by hand`);
4. no match: `internal`, with the message scrubbed.

A pattern is `{ code, find, retryable? }`; it matches when the message contains
one of the plain strings in `find`. The shape is not checked by `classify`
(a malformed rule would throw from the error path, only when a message reaches
it): `check_patterns` checks it once. The order of the built-in patterns is part
of the contract (a message that is both `no such` and `already exists` is
`not_found`).
