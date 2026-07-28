# `lib.lua.strings.transform`

A smaller, focused aggregator over `lib.lua.strings` — casing, padding,
trimming and the prefix-remover, and nothing else. Pure Lua, no `vim` API.

```lua
local transform = require("lib.lua.strings.transform")
```

It re-exports exactly these, straight off `lib.lua.strings.core` and
`lib.lua.strings.remove_prefix`:

```lua
transform.remove_prefix
transform.trim
transform.slugify
transform.kebab_case
transform.snake_case
transform.camel_case
transform.capitalize
transform.uncapitalize
transform.normalize_ws
transform.pad_start
transform.pad_end
transform.pad_center
transform.indent
transform.dedent
```

Deliberately **excluded**: everything from `lib.lua.strings.patterns`,
`.links`, `.utf8`, `.encoding`, `.distance`, `.format`, `.location`, `.case`
and `.wrap` — those live only on the full `lib.lua.strings` aggregator. See
[`../README.md`](../README.md) for the complete surface and per-function
behavior; the functions here behave identically to their `lib.lua.strings`
counterparts, this module is a curated subset, not a reimplementation.

## Usage

```lua
transform.slugify("Hello, World!")   --> "hello-world"
transform.kebab_case("Hello World")  --> "hello-world"
transform.pad_start("7", 3)          --> "  7"
```

Note: `kebab_case`/`snake_case` only insert a separator at an existing word
boundary, not inside a contiguous camelCase/PascalCase run — see the gotcha
in [`../README.md`](../README.md). `transform.dedent` is also currently
broken (raises a Lua error on any input) — see the same file for details; do
not call it.
