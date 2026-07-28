# `lib`

Public aggregator entry point for lib.nvim.

```lua
local lib = require("lib")
lib.notify          -- -> lib.nvim.notify
lib.tables          -- -> lib.lua.tables
```

Delegates to whichever aggregator strategy is configured via
[`lib.config`](config/README.md) (default `"metatable"`) — all three
strategies expose the same flat surface, they only differ in *when* a
submodule loads. See `:help lib.nvim-config` for the full option list.

Prefer direct module paths in plugin code — they are tree-shake friendly and
unaffected by the aggregator strategy:

```lua
local notify = require("lib.nvim.notify")
```
