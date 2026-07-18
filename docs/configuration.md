# Configuration

The only runtime choice is which aggregator strategy `require("lib")` uses. All strategies expose the same surface; they differ only in *when* submodules load. Configure **before** the first `require("lib")`:

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
