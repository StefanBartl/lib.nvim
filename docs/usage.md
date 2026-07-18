# Usage

Direct module paths are recommended in plugin code (tree-shake friendly):

```lua
local notify = require("lib.nvim.notify")
local tables = require("lib.lua.tables")
local map    = require("lib.nvim.map")
```

Or via the aggregator, which resolves keys lazily on first access:

```lua
local lib = require("lib")
lib.notify          -- -> lib.nvim.notify
lib.map             -- -> lib.nvim.map
lib.is_windows()    -- -> lib.nvim.cross.platform.is_windows
```

See [Configuration](configuration.md) for how to choose the aggregator strategy that `require("lib")` uses, and [Namespaces & modules](modules.md) for the full list of available modules.
