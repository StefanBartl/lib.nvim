# EmmyLua/LuaLS annotation reference for this repo

A survey of which [LuaCATS](https://luals.github.io/wiki/annotations/) annotations this tree actually
uses, which real ones it doesn't, and which tags exist outside the spec entirely — written to inform
what `docmap` recognizes and what future source-code annotation is worth adding. Tag counts are exact,
from `grep -rhoE '^\s*---@[A-Za-z_]+' --include="*.lua" lua/ | sort | uniq -c` against this repo at the
time of writing; re-run it yourself if this drifts.

This is a reference and a recommendation, not a mandate — nothing here means "go retrofit all ~250
files." Adopt a tag when the concrete case for it comes up, not in bulk.

## a) Standard tags already used heavily

| Tag | Count | What it's for here |
|---|---|---|
| `@field` | 1476 | Class/alias member declarations in `@types/` files |
| `@param` | 1208 | Function parameters |
| `@return` | 837 | Function return values |
| `@module` | 358 | This repo's own "module path" convention — required on every file, checked by `docmap`'s `missing-module-tag` |
| `@class` | 270 | Structured types in `@types/` files |
| `@type` | 202 | Standalone variable typing |
| `@nodiscard` | 112 | Marks a return value that must not be silently dropped |
| `@meta` | 106 | Marks `@types/init.lua` files as pure-definition, non-executable |
| `@generic` | 59 | Type-agnostic function signatures |
| `@alias` | 48 | Named unions / enum-shaped string literals |
| `@diagnostic` | 5 | Suppressing a specific LuaLS diagnostic on one line |
| `@cast` | 4 | Narrowing a variable's type mid-function |
| `@overload` | 1 | Technically standard, practically almost unused here |

## b) Standard tags, unused in this repo (0 hits), with real value for `docmap`

- **`@deprecated`** — no hits. `docmap`'s function scanner (see [`functions.lua`](../functions.lua))
  recognizes it and renders a deprecation banner + surfaces it in the Functions section. High value:
  this is the single most Doxygen-shaped signal missing today.
- **`@see`** — no hits. Recognized as a cross-reference; `docmap` renders it as a clickable link when
  the target resolves to a known node/function, and the new `dead-see-target` check (mirrors the
  existing `dead-readme-link`) flags it when it doesn't. Core of "Doxygen-like" cross-referencing.
- **`@async`** — no hits. Recognized as a badge on a documented function once function-level scanning
  exists. Medium value on its own; only useful once functions are individually documented.
- **`@enum`** — no hits. This repo currently expresses "one of these string literals" via
  `@alias Foo "a"|"b"|"c"` (see e.g. `Lib.Docmap.Kind`). For a table that's a real *runtime* value (like
  `vim.log.levels`-shaped constants), `@enum` is more accurate than `@alias` — LuaLS then knows the table
  itself is the enum, not just its keys' string shape. Medium value, but a case-by-case call, not a
  blanket replacement for every `@alias`.
- **`@package`/`@private`/`@protected`** — no hits. Would let `docmap` distinguish public vs. internal
  *functions*, not just directories (today the only public/private signal is the `_`-prefix /
  `internal/`-directory convention at module granularity, documented in `doc/lib.nvim.txt`'s
  Conventions section). Medium value, but repo-wide adoption is a separate, later decision — not part
  of this change.
- **`@operator`/`@source`/`@version`/`@vararg`/`@as`** — no hits, low value for this repo specifically:
  no metatable operator overloading anywhere, no multi-Lua-version compatibility matrix to declare
  (`@vararg` is also deprecated upstream in favor of `...`). Listed for completeness, not actively
  recommended.

## c) Tags outside the LuaCATS spec

Already in informal use, tolerated by `scan.lua`'s header parser as an alternative to plain prose:

- **`@brief`** (8 hits), **`@description`** (10 hits) — competing convention for a module's leading
  summary line.

New in this change, recognized by [`functions.lua`](../functions.lua):

- **`@example`** — a code sample attached to a function's doc block, rendered by `docmap` as its own
  fenced block instead of being flattened into prose. Many modules already informally embed a ` ```lua `
  fence in their module-level header prose; `@example` makes the same idea explicit and
  machine-readable at function granularity.
- **`@since`** — deliberately *not* `@version`: LuaLS's `@version` declares which Lua runtime a symbol
  requires (5.1/5.3/JIT/...), a different question from "since when has this function existed in this
  project." A separate tag avoids colliding those two meanings.
