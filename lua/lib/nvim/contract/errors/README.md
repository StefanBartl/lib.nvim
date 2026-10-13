# `lib.nvim.contract.errors`

The error vocabulary of a **machine contract** (`tasks-export/1`, `rules-export/1`,
...): a stable `code`, a `message`, and whether asking again can help
(`retryable`). Moved here from `tasks_nvim.errors` (tasks.nvim@921a0c4); the one
domain-specific part, the matching of a plugin's own messages, is now a hook.

## Codes

`M.CODES` (sorted): `conflict`, `exists`, `forbidden`, `internal`,
`invalid_argument`, `io`, `lock_stuck`, `locked`, `not_found`,
`payload_too_large`, `rollback_incomplete`, `unsupported_schema`.

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
| `fail(code, message, retryable?)` | An error table; `retryable` only when it is the boolean `true`. |
| `scrub(text)` | A Lua error text without where the plugin is installed (`<path>/lua/x/a.lua:3: boom` becomes `x/a.lua:3: boom`). Only the part after the last whitespace or quote is cut. |
| `classify(err, info?, opts?)` | Turn whatever came back into the error a document carries (below). |
| `DETAIL_KEYS` | Keys of `info` a document may show: `id`, `key`, `expected`, `actual`, `written`, `writes`. Never a path. |

`classify`:

1. an `err` that already is an error table (has a `code`) is returned as it is;
2. with `info.code` (the third value some functions give) the code comes from the
   source; `locked` is always retryable; `details` carries only `DETAIL_KEYS`
   (or `opts.detail_keys`);
3. otherwise the **text** is matched: first `opts.patterns` (the plugin's own),
   then the built-in ones, each tried in this order: `not_found` (`is not a
   directory`, `no such`), `exists` (`already exists`), `rollback_incomplete`,
   `io` (`cannot list/read/write/create/update/lock`, `permission`), `locked`
   (`is being written`, retryable), `lock_stuck` (`remove it by hand`);
4. no match: `internal`, with the message scrubbed.

A pattern is `{ code, find, retryable? }`; it matches when the message contains
one of the plain strings in `find`. The order of the built-in patterns is part
of the contract (a message that is both `no such` and `already exists` is
`not_found`).
