# Configuration

The only runtime choice is which aggregator strategy `require("lib")` uses. Every strategy exposes the full common surface — the `Lib` class in [`lua/lib/@types/all_functions.lua`](../lua/lib/@types/all_functions.lua) — and they differ only in *when* submodules load. The `lazy` and `eager` strategies additionally expose a few flattened convenience keys on top of it (`augroup`, `unique` / `unique_by` / `is_unique`, …); those are collected in the `Lib.Strategy.Lazy` class in the same file. Configure **before** the first `require("lib")`:

```lua
require("lib.config").setup({ strategy = "lazy" })
local lib = require("lib")
```

| `strategy`             | Behaviour                                              |
| ---------------------- | ------------------------------------------------------ |
| `"metatable"` (default)| per-key proxy; a submodule loads on first access       |
| `"lazy"`               | eager key registry; submodules load on first access    |
| `"eager"`              | every submodule is required up-front                   |

Direct module paths ignore this setting and are always the most efficient way to consume the library.

## Default strategy

`require("lib")` uses the "metatable" strategy as default:

```lua
require("lib")
local lib = require("lib")
```
