# Quickstart

Require the module you need. Direct requires are the normal path — they are
tree-shake friendly and say in the call site exactly what is being used:

```lua
local notify = require("lib.nvim.notify")
local tables = require("lib.lua.tables")
```

Then, if you would rather have one handle:

```lua
local lib = require("lib")
lib.notify(...) -- -> lib.nvim.notify
```

Which strategy the aggregator uses to resolve those lookups — eager, lazy or
metatable — is [configuration.md](configuration.md).
[usage.md](usage.md) has the rest of the patterns, and
[WORKFLOW.md](WORKFLOW.md) answers the other question: which module for
which job when building a plugin on top.
