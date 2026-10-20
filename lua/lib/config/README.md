# `lib.config`

User-facing configuration for lib.nvim. The only meaningful runtime choice is
which aggregator strategy `require("lib")` uses — all three resolve to the
same public surface, they differ only in *when* submodules load:

- `"metatable"` (default) — per-key proxy, a submodule loads on first access.
- `"lazy"` — eager key registry, submodules load on first access.
- `"eager"` — every submodule is required up-front.

Direct module paths (e.g. `require("lib.nvim.notify")`) are unaffected by
this and are always the most efficient way to consume the library.

## Usage

```lua
-- Must run BEFORE the first require("lib") — the aggregator is resolved once,
-- on that first require; a strategy change after that has no effect and
-- warns instead of silently doing nothing.
require("lib.config").setup({ strategy = "lazy" })
local lib = require("lib")
```

`M.get()` returns the current `Lib.Config.Options`; `M.strategy_module()`
resolves the configured strategy to its module path (falls back to
`"metatable"` on an unknown strategy name, with a warning). See
`@types/init.lua` for `Lib.Config.Options`.

Every `setup()` call starts from the defaults (it is a `lib.lua.config.new` object),
so an option left out of a second call is back at its default.

Keys that are not part of `Lib.Config.Options` are reported before the merge
(`lib.config: ignored config: unknown option 'startegy' (did you mean 'strategy'?)`)
and never stored, so a typo cannot quietly leave the default in force. A
`strategy` that is none of the three falls back to `"metatable"`, with a warning.
